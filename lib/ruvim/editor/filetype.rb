# frozen_string_literal: true

module RuVim
  class Editor
    # Filetype detection and assignment
    module Filetype
      def detect_filetype(path)
        p = path.to_s
        return nil if p.empty?

        base = File.basename(p)

        # Basename-based detection (exact match, then prefix)
        base_ft = Lang::Registry.detect_by_basename(base)
        return base_ft if base_ft

        # Extension-based detection
        ext_ft = Lang::Registry.detect_by_extension(File.extname(base))
        return ext_ft if ext_ft

        detect_filetype_from_shebang(p)
      end

      def assign_filetype(buffer, ft)
        buffer.options["filetype"] = ft
        buffer.lang_module = resolve_lang_module(ft)
        apply_filetype_defaults(buffer, ft)
      end

      def apply_filetype_defaults(buffer, ft)
        Lang::Registry.buffer_defaults_for(ft).each do |key, value|
          buffer.options[key] = value unless buffer.options.key?(key)
        end
      end

      private

      def resolve_lang_module(ft)
        Lang::Registry.resolve_module(ft)
      end

      def detect_filetype_from_shebang(path)
        line = read_first_line(path)
        return nil unless line.start_with?("#!")

        cmd = shebang_command_name(line)
        return nil if cmd.nil? || cmd.empty?

        Lang::Registry.detect_by_shebang(cmd)
      rescue StandardError
        nil
      end

      def read_first_line(path)
        return "" unless path && !path.empty?
        return "" unless File.file?(path)

        File.open(path, "rb") do |f|
          (f.gets || "").to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
      rescue StandardError
        ""
      end

      def shebang_command_name(line)
        src = line.to_s.sub(/\A#!/, "").strip
        return nil if src.empty?

        tokens = src.split(/\s+/)
        return nil if tokens.empty?

        prog = tokens[0].to_s
        if File.basename(prog) == "env"
          i = 1
          while i < tokens.length && tokens[i].start_with?("-")
            if tokens[i] == "-S"
              i += 1
              break
            end
            i += 1
          end
          prog = tokens[i].to_s
        end

        File.basename(prog)
      end

      def assign_detected_filetype(buffer)
        ft = detect_filetype(buffer.path)
        assign_filetype(buffer, ft) if ft && !ft.empty?
        buffer
      end
    end
  end
end
