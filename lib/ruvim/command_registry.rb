module RuVim
  class CommandRegistry
    CommandSpec = Struct.new(
      :id,
      :call,
      :desc,
      :source,
      keyword_init: true
    )

    include Singleton

    def initialize
      @specs = {}
    end

    def register(id, call:, desc: "", source: :builtin)
      key = id.to_s
      @specs[key] = CommandSpec.new(id: key, call:, desc:, source:)
    end

    def fetch(id)
      @specs.fetch(id.to_s)
    end

    def registered?(id)
      @specs.key?(id.to_s)
    end

    def all
      @specs.values.sort_by(&:id)
    end

    def clear!
      @specs.clear
    end
  end
end
