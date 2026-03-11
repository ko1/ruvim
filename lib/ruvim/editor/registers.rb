# frozen_string_literal: true

module RuVim
  class Editor
    module Registers
      def registers
        @registers
      end

      def set_register(name = "\"", text:, type: :charwise)
        key = name.to_s
        return { text: text, type: type } if key == "_"

        payload = write_register_payload(key, text: text, type: type)
        write_clipboard_register(key, payload)
        if key == "\""
          if (default_clip = clipboard_default_register_key)
            mirror = write_register_payload(default_clip, text: payload[:text], type: payload[:type])
            write_clipboard_register(default_clip, mirror)
          end
        end
        @registers["\""] = payload unless key == "\""
        payload
      end

      def store_operator_register(name = "\"", text:, type:, kind:)
        key = (name || "\"")
        payload = { text: text, type: type }
        return payload if key == "_"

        written = set_register(key, text: payload[:text], type: payload[:type])
        op_payload = dup_register_payload(written)

        case kind
        when :yank
          @registers["0"] = dup_register_payload(op_payload)
        when :delete, :change
          rotate_delete_registers!(op_payload)
        end

        written
      end

      def get_register(name = "\"")
        key = name.to_s.downcase
        if key == "\""
          if (default_clip = clipboard_default_register_key)
            if (payload = read_clipboard_register(default_clip))
              @registers["\""] = dup_register_payload(payload)
              return @registers["\""]
            end
          end
        end
        return read_clipboard_register(key) if clipboard_register?(key)

        @registers[key]
      end

      def set_active_register(name)
        @active_register_name = name.to_s
      end

      def active_register_name
        @active_register_name
      end

      def consume_active_register(default = "\"")
        name = @active_register_name || default
        @active_register_name = nil
        name
      end

      private

      def write_register_payload(key, text:, type:)
        if key.match?(/\A[A-Z]\z/)
          base = key.downcase
          prev = @registers[base]
          payload = { text: "#{prev ? prev[:text] : ""}#{text}", type: type }
          @registers[base] = payload
        else
          payload = { text: text, type: type }
          @registers[key.downcase] = payload
        end
        payload
      end

      def rotate_delete_registers!(payload)
        9.downto(2) do |i|
          prev = @registers[(i - 1).to_s]
          if prev
            @registers[i.to_s] = dup_register_payload(prev)
          else
            @registers.delete(i.to_s)
          end
        end
        @registers["1"] = dup_register_payload(payload)
      end

      def dup_register_payload(payload)
        return nil unless payload

        { text: payload[:text].dup, type: payload[:type] }
      end

      def clipboard_register?(key)
        key == "+" || key == "*"
      end

      def clipboard_default_register_key
        spec = @global_options["clipboard"].to_s
        parts = spec.split(",").map { |s| s.strip.downcase }.reject(&:empty?)
        return "+" if parts.include?("unnamedplus")
        return "*" if parts.include?("unnamed")

        nil
      end

      def write_clipboard_register(key, payload)
        return unless clipboard_register?(key.downcase)

        RuVim::Clipboard.write(payload[:text])
      end

      def read_clipboard_register(key)
        text = RuVim::Clipboard.read
        if text
          payload = { text: text, type: text.end_with?("\n") ? :linewise : :charwise }
          @registers[key] = payload
        end
        @registers[key]
      end
    end
  end
end
