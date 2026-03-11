# frozen_string_literal: true

module RuVim
  class Editor
    module LayoutTree
      private

      def tree_leaves(node)
        return [] if node.nil?
        return [node[:id]] if node[:type] == :window

        node[:children].flat_map { |c| tree_leaves(c) }
      end

      def tree_deep_dup(node)
        return nil if node.nil?
        return { type: :window, id: node[:id] } if node[:type] == :window

        { type: node[:type], children: node[:children].map { |c| tree_deep_dup(c) } }
      end

      def tree_split_leaf(node, target_id, split_type, new_leaf, place)
        if node[:type] == :window
          if node[:id] == target_id
            children = place == :before ? [new_leaf, node] : [node, new_leaf]
            return { type: split_type, children: children }
          end
          return node
        end

        new_children = node[:children].flat_map do |child|
          result = tree_split_leaf(child, target_id, split_type, new_leaf, place)
          if result[:type] == node[:type] && result != child
            result[:children]
          else
            [result]
          end
        end

        { type: node[:type], children: new_children }
      end

      def tree_remove(node, target_id)
        return nil if node.nil?
        return nil if node[:type] == :window && node[:id] == target_id
        return node if node[:type] == :window

        new_children = node[:children].filter_map { |c| tree_remove(c, target_id) }
        return nil if new_children.empty?
        return new_children.first if new_children.length == 1

        { type: node[:type], children: new_children }
      end

      def tree_path_has_split_type?(node, target_id, split_type)
        return false if node.nil?
        return false if node[:type] == :window
        node[:children].each do |child|
          if tree_subtree_contains?(child, target_id)
            return true if node[:type] == split_type
            return tree_path_has_split_type?(child, target_id, split_type)
          end
        end
        false
      end

      def tree_subtree_contains?(node, target_id)
        return false if node.nil?
        return node[:id] == target_id if node[:type] == :window
        node[:children].any? { |c| tree_subtree_contains?(c, target_id) }
      end

      def tree_compute_rects(node, top:, left:, height:, width:)
        return {} if node.nil?

        if node[:type] == :window
          return { node[:id] => { top: top, left: left, height: height, width: width } }
        end

        children = node[:children]
        n = children.length
        rects = {}

        case node[:type]
        when :vsplit
          w_each = width / n.to_f
          children.each_with_index do |child, i|
            rects.merge!(tree_compute_rects(child, top: top, left: left + i * w_each, height: height, width: w_each))
          end
        when :hsplit
          h_each = height / n.to_f
          children.each_with_index do |child, i|
            rects.merge!(tree_compute_rects(child, top: top + i * h_each, left: left, height: h_each, width: width))
          end
        end

        rects
      end

      def find_parent_split(node, target_id, dir)
        return nil unless node.is_a?(Hash) && node[:children]

        wanted_type = case dir
                      when :height_increase, :height_decrease then :hsplit
                      when :width_increase, :width_decrease then :vsplit
                      end

        node[:children].each_with_index do |child, i|
          if child[:type] == :window && child[:id] == target_id
            return [node[:type], node, i] if node[:type] == wanted_type
          elsif child[:children]
            result = find_parent_split(child, target_id, dir)
            return result if result
          end
        end

        nil
      end

      def clear_weights(node)
        return unless node.is_a?(Hash)

        node.delete(:weights) if node.key?(:weights)
        node[:children]&.each { |c| clear_weights(c) }
      end
    end
  end
end
