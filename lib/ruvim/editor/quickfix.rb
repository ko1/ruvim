# frozen_string_literal: true

module RuVim
  class Editor
    module Quickfix
      def quickfix_items
        @quickfix_list[:items]
      end

      def quickfix_index
        @quickfix_list[:index]
      end

      def set_quickfix_list(items)
        ary = Array(items).map { |it| normalize_location(it)&.merge(text: (it[:text] || it["text"]).to_s) }.compact
        @quickfix_list = { items: ary, index: nil }
        @quickfix_list
      end

      def current_quickfix_item
        idx = @quickfix_list[:index]
        idx ? @quickfix_list[:items][idx] : nil
      end

      def move_quickfix(step)
        items = @quickfix_list[:items]
        return nil if items.empty?

        cur = @quickfix_list[:index]
        @quickfix_list[:index] = if cur.nil?
                                    step.to_i > 0 ? 0 : items.length - 1
                                  else
                                    (cur + step.to_i) % items.length
                                  end
        current_quickfix_item
      end

      def select_quickfix(index)
        items = @quickfix_list[:items]
        return nil if items.empty?

        i = [[index.to_i, 0].max, items.length - 1].min
        @quickfix_list[:index] = i
        current_quickfix_item
      end

      def location_list(window_id = current_window_id)
        @location_lists[window_id]
      end

      def location_items(window_id = current_window_id)
        location_list(window_id)[:items]
      end

      def set_location_list(items, window_id: current_window_id)
        ary = Array(items).map { |it| normalize_location(it)&.merge(text: (it[:text] || it["text"]).to_s) }.compact
        @location_lists[window_id] = { items: ary, index: nil }
        @location_lists[window_id]
      end

      def current_location_list_item(window_id = current_window_id)
        list = location_list(window_id)
        idx = list[:index]
        idx ? list[:items][idx] : nil
      end

      def move_location_list(step, window_id: current_window_id)
        list = location_list(window_id)
        items = list[:items]
        return nil if items.empty?

        cur = list[:index]
        list[:index] = if cur.nil?
                         step.to_i > 0 ? 0 : items.length - 1
                       else
                         (cur + step.to_i) % items.length
                       end
        current_location_list_item(window_id)
      end

      def select_location_list(index, window_id: current_window_id)
        list = location_list(window_id)
        items = list[:items]
        return nil if items.empty?

        i = [[index.to_i, 0].max, items.length - 1].min
        list[:index] = i
        current_location_list_item(window_id)
      end
    end
  end
end
