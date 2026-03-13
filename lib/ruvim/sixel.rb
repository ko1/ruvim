# frozen_string_literal: true

require "zlib"

module RuVim
  module Sixel
    module_function

    # Encode PNG binary data to a sixel string.
    # Returns { sixel: String, rows: Integer } or nil on failure.
    def encode(png_data, max_width_cells:, max_height_cells:, cell_width: 8, cell_height: 16)
      img = PNGDecoder.decode(png_data)
      return nil unless img

      max_px_w = max_width_cells * cell_width
      max_px_h = max_height_cells * cell_height

      w = img[:width]
      h = img[:height]
      pixels = img[:pixels]

      if w > max_px_w || h > max_px_h
        scale = [max_px_w.to_f / w, max_px_h.to_f / h].min
        new_w = [(w * scale).to_i, 1].max
        new_h = [(h * scale).to_i, 1].max
        pixels = Resizer.resize(pixels, w, h, new_w, new_h)
        w = new_w
        h = new_h
      end

      sixel = Encoder.encode(pixels, w, h)
      rows = (h + cell_height - 1) / cell_height
      { sixel: sixel, rows: rows }
    rescue StandardError
      nil
    end

    # --- PNG Decoder ---

    module PNGDecoder
      PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*").freeze

      class Error < StandardError; end

      module_function

      def decode(data)
        raise Error, "Not a PNG" unless data.start_with?(PNG_SIGNATURE)

        pos = 8
        ihdr = nil
        idat_chunks = []

        while pos + 8 <= data.bytesize
          length = data.byteslice(pos, 4).unpack1("N")
          type = data.byteslice(pos + 4, 4)
          chunk_data = data.byteslice(pos + 8, length)
          pos += 12 + length  # length(4) + type(4) + data(length) + crc(4)

          case type
          when "IHDR"
            ihdr = parse_ihdr(chunk_data)
          when "IDAT"
            idat_chunks << chunk_data
          when "IEND"
            break
          end
        end

        raise Error, "Missing IHDR" unless ihdr
        raise Error, "Unsupported bit depth: #{ihdr[:bit_depth]}" unless ihdr[:bit_depth] == 8
        raise Error, "Unsupported color type: #{ihdr[:color_type]}" unless [2, 6].include?(ihdr[:color_type])

        raw = Zlib::Inflate.inflate(idat_chunks.join)
        unfilter(raw, ihdr)
      end

      def parse_ihdr(data)
        width, height, bit_depth, color_type = data.unpack("NNC2")
        { width: width, height: height, bit_depth: bit_depth, color_type: color_type }
      end

      def unfilter(raw, ihdr)
        w = ihdr[:width]
        h = ihdr[:height]
        bpp = ihdr[:color_type] == 6 ? 4 : 3  # RGBA or RGB
        stride = w * bpp + 1  # +1 for filter byte

        pixels = Array.new(h) { Array.new(w) }
        prev_row = Array.new(w * bpp, 0)

        h.times do |y|
          offset = y * stride
          filter = raw.getbyte(offset)
          row_bytes = Array.new(w * bpp)

          (w * bpp).times do |i|
            x_byte = raw.getbyte(offset + 1 + i)
            a = i >= bpp ? row_bytes[i - bpp] : 0
            b = prev_row[i]
            c = i >= bpp ? prev_row[i - bpp] : 0

            row_bytes[i] = case filter
                           when 0 then x_byte
                           when 1 then (x_byte + a) & 0xFF
                           when 2 then (x_byte + b) & 0xFF
                           when 3 then (x_byte + ((a + b) / 2)) & 0xFF
                           when 4 then (x_byte + paeth(a, b, c)) & 0xFF
                           else x_byte
                           end
          end

          w.times do |x|
            base = x * bpp
            pixels[y][x] = [row_bytes[base], row_bytes[base + 1], row_bytes[base + 2]]
          end

          prev_row = row_bytes
        end

        { width: w, height: h, pixels: pixels }
      end

      def paeth(a, b, c)
        p_val = a + b - c
        pa = (p_val - a).abs
        pb = (p_val - b).abs
        pc = (p_val - c).abs
        if pa <= pb && pa <= pc
          a
        elsif pb <= pc
          b
        else
          c
        end
      end
    end

    # --- Nearest-neighbor resize ---

    module Resizer
      module_function

      def resize(pixels, src_w, src_h, dst_w, dst_h)
        return pixels if src_w == dst_w && src_h == dst_h

        Array.new(dst_h) do |y|
          src_y = (y * src_h / dst_h).clamp(0, src_h - 1)
          Array.new(dst_w) do |x|
            src_x = (x * src_w / dst_w).clamp(0, src_w - 1)
            pixels[src_y][src_x]
          end
        end
      end
    end

    # --- Uniform 6-level quantizer (216 colors) ---

    module Quantizer
      module_function

      # Map 0-255 to 0-5
      def quantize(r, g, b)
        ri = (r * 5.0 / 255).round
        gi = (g * 5.0 / 255).round
        bi = (b * 5.0 / 255).round
        ri * 36 + gi * 6 + bi
      end

      # Return [r%, g%, b%] in 0-100 range for sixel color register
      def color_register(index)
        bi = index % 6
        gi = (index / 6) % 6
        ri = index / 36
        [ri * 20, gi * 20, bi * 20]
      end
    end

    # --- Sixel encoder ---

    module Encoder
      module_function

      def encode(pixels, width, height)
        # DCS P1;P2;P3 q — P2=1: no-scrolling mode (prevents terminal from
        # scrolling when image extends near bottom of screen)
        out = +"\eP0;1q"

        # Raster attributes: "Pan;Pad;Ph;Pv" — aspect ratio 1:1, image dimensions
        out << "\"1;1;#{width};#{height}"

        # Collect used colors and define registers
        used = {}
        height.times do |y|
          width.times do |x|
            r, g, b = pixels[y][x]
            idx = Quantizer.quantize(r, g, b)
            used[idx] = true
          end
        end

        used.each_key do |idx|
          r, g, b = Quantizer.color_register(idx)
          out << "##{idx};2;#{r};#{g};#{b}"
        end

        # Encode bands of 6 rows
        y = 0
        while y < height
          band_height = [6, height - y].min

          # Group pixels by color for this band
          color_data = {}
          band_height.times do |dy|
            width.times do |x|
              r, g, b = pixels[y + dy][x]
              idx = Quantizer.quantize(r, g, b)
              color_data[idx] ||= Array.new(width, 0)
              color_data[idx][x] |= (1 << dy)
            end
          end

          # Each color: select → data → $ (CR back to start of band)
          # Last color in band: no $ needed (- or ST follows)
          keys = color_data.keys
          keys.each_with_index do |idx, ci|
            out << "##{idx}"
            color_data[idx].each { |bits| out << (bits + 63).chr }
            out << "$" unless ci == keys.length - 1
          end

          y += 6
          out << "-" if y < height  # graphics newline (next band)
        end

        out << "\e\\"
        out
      end
    end

    # Load a PNG image from path (resolved relative to buffer_dir),
    # encode to sixel, and cache the result.
    # Returns { sixel: String, rows: Integer } or nil.
    def load_image(path, buffer_dir:, max_width_cells:, max_height_cells:, cell_width: 8, cell_height: 16, cache: nil)
      full_path = resolve_path(path, buffer_dir)
      return nil unless full_path && File.exist?(full_path)

      mtime = File.mtime(full_path).to_i
      if cache
        cached = cache.get(full_path, mtime, max_width_cells, max_height_cells)
        return cached if cached
      end

      png_data = File.binread(full_path)
      result = encode(png_data, max_width_cells: max_width_cells, max_height_cells: max_height_cells,
                                cell_width: cell_width, cell_height: cell_height)
      cache&.put(full_path, mtime, max_width_cells, max_height_cells, result) if result
      result
    rescue StandardError
      nil
    end

    def resolve_path(path, buffer_dir)
      return nil if path.nil? || path.empty?

      if path.start_with?("http://", "https://")
        return download(path)
      end

      return path if path.start_with?("/")

      if buffer_dir && !buffer_dir.empty?
        File.expand_path(path, buffer_dir)
      else
        File.expand_path(path)
      end
    end

    def download(url)
      require "net/http"
      require "uri"
      require "digest"

      cache_dir = File.join(Dir.tmpdir, "ruvim_img_cache")
      Dir.mkdir(cache_dir) unless Dir.exist?(cache_dir)
      cache_file = File.join(cache_dir, Digest::SHA256.hexdigest(url) + ".png")
      return cache_file if File.exist?(cache_file)

      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      File.binwrite(cache_file, response.body)
      cache_file
    rescue StandardError
      nil
    end

    # --- Image cache ---

    class Cache
      def initialize
        @entries = {}
      end

      def get(path, mtime, width, height)
        key = [path, mtime, width, height]
        @entries[key]
      end

      def put(path, mtime, width, height, result)
        key = [path, mtime, width, height]
        # Limit cache size
        @entries.shift if @entries.size >= 64
        @entries[key] = result
      end
    end
  end
end
