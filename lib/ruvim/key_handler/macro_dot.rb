# frozen_string_literal: true

module RuVim
  class KeyHandler
    module MacroDot
      private

      # --- Macro recording / playback ---

      def start_macro_record_pending
        @macro_record_pending = true
        @editor.echo("q")
      end

      def toggle_macro_recording_or_start_pending
        if @editor.macro_recording?
          stop_macro_recording
        else
          start_macro_record_pending
        end
      end

      def finish_macro_record_pending(token)
        @macro_record_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9]\z/)
          @editor.echo_error("Invalid macro register")
          return
        end

        unless @editor.start_macro_recording(token)
          @editor.echo("Failed to start recording")
          return
        end
        @skip_record_for_current_key = true
        @editor.echo("recording @#{token}")
      end

      def stop_macro_recording
        reg = @editor.macro_recording_name
        @editor.stop_macro_recording
        @editor.echo("recording @#{reg} stopped")
      end

      def start_macro_play_pending
        @macro_play_pending = true
        @editor.echo("@")
      end

      def finish_macro_play_pending(token)
        @macro_play_pending = false
        if token == "\e"
          @editor.clear_message
          return
        end
        name =
          if token == "@"
            @last_macro_name
          elsif token.is_a?(String) && token.match?(/\A[A-Za-z0-9]\z/)
            token
          end
        unless name
          @editor.echo_error("Invalid macro register")
          return
        end

        count = @editor.pending_count
        @editor.pending_count = nil
        play_macro(name, count:)
      end

      def play_macro(name, count:)
        reg = name.to_s.downcase
        keys = @editor.macro_keys(reg)
        if keys.nil? || keys.empty?
          @editor.echo("Macro empty: #{reg}")
          return
        end

        @macro_play_stack ||= []
        if @macro_play_stack.include?(reg) || @macro_play_stack.length >= 20
          @editor.echo("Macro recursion blocked: #{reg}")
          return
        end

        @last_macro_name = reg
        @macro_play_stack << reg
        @suspend_macro_recording_depth = (@suspend_macro_recording_depth || 0) + 1
        [count.to_i, 1].max.times do
          keys.each { |k| handle(dup_macro_runtime_key(k)) }
        end
        @editor.echo("@#{reg}")
      ensure
        @suspend_macro_recording_depth = [(@suspend_macro_recording_depth || 1) - 1, 0].max
        @macro_play_stack.pop if @macro_play_stack && !@macro_play_stack.empty?
      end

      def record_macro_key_if_needed(key)
        return if @skip_record_for_current_key
        return unless @editor.macro_recording?
        return if (@suspend_macro_recording_depth || 0).positive?
        return if (@dot_replay_depth || 0).positive?

        @editor.record_macro_key(key)
      end

      def dup_macro_runtime_key(key)
        case key
        when String
          key.dup
        when Array
          key.map { |v| v.is_a?(String) ? v.dup : v }
        else
          key
        end
      end

      # --- Dot repeat ---

      def repeat_last_change
        keys = @last_change_keys
        if keys.nil? || keys.empty?
          @editor.echo("No previous change")
          return
        end

        @dot_replay_depth = (@dot_replay_depth || 0) + 1
        keys.each { |k| handle(dup_macro_runtime_key(k)) }
        @editor.echo(".")
      ensure
        @dot_replay_depth = [(@dot_replay_depth || 1) - 1, 0].max
      end

      def maybe_record_simple_dot_change(invocation, matched_keys, count)
        return if (@dot_replay_depth || 0).positive?

        case invocation.id
        when "buffer.delete_char", "buffer.delete_motion", "buffer.join_lines", "buffer.swapcase_char", "buffer.paste_after", "buffer.paste_before"
          record_last_change_keys(count_prefixed_keys(count, matched_keys))
        when "mode.insert", "mode.append", "mode.append_line_end", "mode.insert_nonblank", "mode.open_below", "mode.open_above", "buffer.substitute_char", "buffer.change_motion", "buffer.change_line"
          begin_dot_change_capture(count_prefixed_keys(count, matched_keys)) if @editor.mode == :insert
        end
      end

      def begin_dot_change_capture(prefix_keys)
        return if (@dot_replay_depth || 0).positive?

        @dot_change_capture_keys = Array(prefix_keys).map { |k| dup_macro_runtime_key(k) }
        @dot_change_capture_active = true
      end

      def append_dot_change_capture_key(key)
        return unless @dot_change_capture_active
        return if (@dot_replay_depth || 0).positive?

        @dot_change_capture_keys ||= []
        @dot_change_capture_keys << dup_macro_runtime_key(key)
      end

      def finish_dot_change_capture
        return unless @dot_change_capture_active

        keys = Array(@dot_change_capture_keys)
        @dot_change_capture_active = false
        @dot_change_capture_keys = nil
        record_last_change_keys(keys)
      end

      def record_last_change_keys(keys)
        return if (@dot_replay_depth || 0).positive?

        @last_change_keys = Array(keys).map { |k| dup_macro_runtime_key(k) }
      end

      def count_prefixed_keys(count, keys)
        c = count.to_i
        prefix = c > 1 ? c.to_s.each_char.to_a : []
        prefix + Array(keys)
      end
    end
  end
end
