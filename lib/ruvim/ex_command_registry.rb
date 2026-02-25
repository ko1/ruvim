module RuVim
  class ExCommandRegistry
    ExCommandSpec = Struct.new(
      :name,
      :call,
      :aliases,
      :desc,
      :nargs,
      :bang,
      :source,
      keyword_init: true
    )

    include Singleton

    def initialize
      @specs = {}
      @lookup = {}
    end

    def register(name, call:, aliases: [], desc: "", nargs: :any, bang: false, source: :builtin)
      canonical = name.to_s
      if @specs.key?(canonical)
        raise RuVim::CommandError, "Ex command already exists: #{canonical}"
      end
      spec = ExCommandSpec.new(
        name: canonical,
        call: call,
        aliases: aliases.map(&:to_s),
        desc: desc,
        nargs: nargs,
        bang: bang,
        source: source
      )

      names = [canonical, *spec.aliases]
      names.each do |n|
        existing = @lookup[n]
        if existing && existing != canonical
          raise RuVim::CommandError, "Ex command name collision: #{n}"
        end
      end

      @specs[canonical] = spec
      names.each { |n| @lookup[n] = canonical }
      spec
    end

    def resolve(name)
      canonical = @lookup[name.to_s]
      canonical && @specs[canonical]
    end

    def fetch(name)
      resolve(name) || raise(RuVim::CommandError, "Not an editor command: #{name}")
    end

    def all
      @specs.values.sort_by(&:name)
    end

    def registered?(name)
      !!resolve(name)
    end

    def unregister(name)
      spec = resolve(name.to_s)
      return nil unless spec

      @specs.delete(spec.name)
      @lookup.delete_if { |_k, v| v == spec.name }
      spec
    end

    def clear!
      @specs.clear
      @lookup.clear
    end
  end
end
