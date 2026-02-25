module RuVim
  class Buffer
    attr_reader :id, :kind, :name
    attr_accessor :path
    attr_reader :options
    attr_writer :modified

    def self.from_file(id:, path:)
      lines =
        if File.exist?(path)
          data = decode_text(File.binread(path))
          split_lines(data)
        else
          [""]
        end
      new(id:, path:, lines:)
    end

    def self.split_lines(data)
      return [""] if data.empty?

      lines = data.split("\n", -1)
      if data.end_with?("\n")
        lines.pop
      end
      lines = [""] if lines.empty?
      lines
    end

    def self.decode_text(bytes)
      s = bytes.to_s.dup
      return s if s.encoding == Encoding::UTF_8 && s.valid_encoding?

      utf8 = s.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?

      ext = Encoding.default_external
      if ext && ext != Encoding::UTF_8
        return s.dup.force_encoding(ext).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      utf8.scrub
    rescue StandardError
      s.dup.force_encoding(Encoding::UTF_8).scrub
    end

    def initialize(id:, path: nil, lines: [""], kind: :file, name: nil, readonly: false, modifiable: true)
      @id = id
      @path = path
      @kind = kind.to_sym
      @name = name
      @lines = lines.dup
      @lines = [""] if @lines.empty?
      @modified = false
      @readonly = !!readonly
      @modifiable = !!modifiable
      @undo_stack = []
      @redo_stack = []
      @change_group_depth = 0
      @group_before_snapshot = nil
      @group_changed = false
      @recording_suspended = false
      @options = {}
    end

    def lines
      @lines
    end

    def modified?
      !!@modified
    end

    def readonly?
      @readonly
    end

    def readonly=(value)
      @readonly = !!value
    end

    def modifiable?
      @modifiable
    end

    def modifiable=(value)
      @modifiable = !!value
    end

    def file_buffer?
      @kind == :file
    end

    def intro_buffer?
      @kind == :intro
    end

    def virtual_buffer?
      !file_buffer?
    end

    def display_name
      @name || @path || "[No Name]"
    end

    def configure_special!(kind:, name: nil, readonly: true, modifiable: false)
      @kind = kind.to_sym
      @name = name
      @readonly = !!readonly
      @modifiable = !!modifiable
      self
    end

    def become_normal_empty_buffer!
      @kind = :file
      @name = nil
      @path = nil
      @readonly = false
      @modifiable = true
      @lines = [""]
      @modified = false
      @undo_stack.clear
      @redo_stack.clear
      @change_group_depth = 0
      @group_before_snapshot = nil
      @group_changed = false
      self
    end

    def can_undo?
      !@undo_stack.empty?
    end

    def can_redo?
      !@redo_stack.empty?
    end

    def begin_change_group
      @change_group_depth += 1
      nil
    end

    def end_change_group
      return nil if @change_group_depth.zero?

      @change_group_depth -= 1
      return nil unless @change_group_depth.zero?

      if @group_changed && @group_before_snapshot
        @undo_stack << @group_before_snapshot
        @redo_stack.clear
      end
      @group_before_snapshot = nil
      @group_changed = false
      nil
    end

    def undo!
      close_change_group_if_open
      return false unless can_undo?

      current = snapshot
      prev = @undo_stack.pop
      with_recording_suspended do
        restore_snapshot(prev)
      end
      @redo_stack << current
      true
    end

    def redo!
      close_change_group_if_open
      return false unless can_redo?

      current = snapshot
      nxt = @redo_stack.pop
      with_recording_suspended do
        restore_snapshot(nxt)
      end
      @undo_stack << current
      true
    end

    def line_count
      @lines.length
    end

    def line_at(row)
      @lines.fetch(row)
    end

    def line_length(row)
      @lines.fetch(row).length
    end

    def insert_char(row, col, char)
      record_change_before_mutation!
      line = @lines.fetch(row)
      @lines[row] = line.dup.insert(col, char)
      @modified = true
    end

    def insert_text(row, col, text)
      text.each_char do |ch|
        if ch == "\n"
          row, col = insert_newline(row, col)
        else
          insert_char(row, col, ch)
          col += 1
        end
      end
      [row, col]
    end

    def insert_newline(row, col)
      record_change_before_mutation!
      line = @lines.fetch(row)
      head = line[0...col]
      tail = line[col..] || ""
      @lines[row] = head
      @lines.insert(row + 1, tail)
      @modified = true
      [row + 1, 0]
    end

    def backspace(row, col)
      if col > 0
        record_change_before_mutation!
        line = @lines.fetch(row)
        @lines[row] = line[0...(col - 1)] + line[col..].to_s
        @modified = true
        return [row, col - 1]
      end

      return [row, col] if row.zero?

      record_change_before_mutation!
      prev = @lines.fetch(row - 1)
      cur = @lines.fetch(row)
      new_col = prev.length
      @lines[row - 1] = prev + cur
      @lines.delete_at(row)
      @modified = true
      [row - 1, new_col]
    end

    def delete_char(row, col)
      line = @lines.fetch(row)
      if col < line.length
        record_change_before_mutation!
        @lines[row] = line[0...col] + line[(col + 1)..].to_s
        @modified = true
        return true
      end

      return false if row >= @lines.length - 1

      record_change_before_mutation!
      @lines[row] = line + @lines[row + 1]
      @lines.delete_at(row + 1)
      @modified = true
      true
    end

    def delete_line(row)
      row = [[row, 0].max, @lines.length - 1].min
      record_change_before_mutation!
      deleted = @lines.delete_at(row)
      @lines << "" if @lines.empty?
      @modified = true
      deleted
    end

    def delete_span(start_row, start_col, end_row, end_col)
      s_row, s_col, e_row, e_col = normalize_span(start_row, start_col, end_row, end_col)
      return false if s_row == e_row && s_col == e_col

      record_change_before_mutation!

      if s_row == e_row
        line = @lines.fetch(s_row)
        @lines[s_row] = line[0...s_col] + line[e_col..].to_s
      else
        head = @lines.fetch(s_row)[0...s_col]
        tail = @lines.fetch(e_row)[e_col..].to_s
        @lines[s_row] = head + tail
        (e_row - s_row).times { @lines.delete_at(s_row + 1) }
      end

      @lines << "" if @lines.empty?
      @modified = true
      true
    end

    def span_text(start_row, start_col, end_row, end_col)
      s_row, s_col, e_row, e_col = normalize_span(start_row, start_col, end_row, end_col)
      return "" if s_row == e_row && s_col == e_col

      if s_row == e_row
        return @lines.fetch(s_row)[s_col...e_col].to_s
      end

      parts = []
      parts << @lines.fetch(s_row)[s_col..].to_s
      ((s_row + 1)...e_row).each { |row| parts << @lines.fetch(row) }
      parts << @lines.fetch(e_row)[0...e_col].to_s
      parts.join("\n")
    end

    def line_block_text(start_row, count = 1)
      rows = @lines[start_row, count] || []
      rows.join("\n") + "\n"
    end

    def insert_lines_at(index, new_lines)
      lines = Array(new_lines).map(&:to_s)
      return if lines.empty?

      record_change_before_mutation!
      idx = [[index, 0].max, @lines.length].min
      @lines.insert(idx, *lines)
      @modified = true
    end

    def replace_all_lines!(new_lines)
      record_change_before_mutation!
      @lines = Array(new_lines).map(&:dup)
      @lines = [""] if @lines.empty?
      @modified = true
    end

    def write_to(path = nil)
      raise RuVim::CommandError, "Buffer is readonly" if readonly?

      target = path || @path
      raise RuVim::CommandError, "No file name" if target.nil? || target.empty?

      File.binwrite(target, @lines.join("\n"))
      @path = target
      @modified = false
      target
    end

    def reload_from_file!(path = nil)
      target = path || @path
      raise RuVim::CommandError, "No file name" if target.nil? || target.empty?

      data = File.exist?(target) ? self.class.decode_text(File.binread(target)) : ""
      @lines = self.class.split_lines(data)
      @path = target
      @modified = false
      @undo_stack.clear
      @redo_stack.clear
      @change_group_depth = 0
      @group_before_snapshot = nil
      @group_changed = false
      target
    end

    private

    def normalize_span(start_row, start_col, end_row, end_col)
      a_before_b = (start_row < end_row) || (start_row == end_row && start_col <= end_col)
      s_row, s_col, e_row, e_col =
        if a_before_b
          [start_row, start_col, end_row, end_col]
        else
          [end_row, end_col, start_row, start_col]
        end
      [s_row, s_col, e_row, e_col]
    end

    def close_change_group_if_open
      return if @change_group_depth.zero?

      @change_group_depth = 1
      end_change_group
    end

    def record_change_before_mutation!
      ensure_modifiable!
      return if @recording_suspended

      if @change_group_depth.positive?
        unless @group_changed
          @group_before_snapshot = snapshot
          @group_changed = true
        end
        return
      end

      @undo_stack << snapshot
      @redo_stack.clear
    end

    def ensure_modifiable!
      raise RuVim::CommandError, "Buffer is not modifiable" unless modifiable?
    end

    def snapshot
      {
        lines: @lines.map(&:dup),
        modified: @modified
      }
    end

    def restore_snapshot(snap)
      @lines = snap.fetch(:lines).map(&:dup)
      @lines = [""] if @lines.empty?
      @modified = snap.fetch(:modified)
    end

    def with_recording_suspended
      prev = @recording_suspended
      @recording_suspended = true
      yield
    ensure
      @recording_suspended = prev
    end
  end
end
