module RuVim
  module KeywordChars
    module_function

    DEFAULT_CHAR_CLASS = "[:alnum:]_".freeze
    DEFAULT_REGEX = /[[:alnum:]_]/.freeze

    def char_class(raw)
      spec = raw.to_s
      return DEFAULT_CHAR_CLASS if spec.empty?

      @char_class_cache ||= {}
      return @char_class_cache[spec] if @char_class_cache.key?(spec)

      extra = []
      spec.split(",").each do |tok|
        t = tok.strip
        next if t.empty? || t == "@"

        if t.length == 1
          extra << Regexp.escape(t)
        elsif t.match?(/\A\d+-\d+\z/)
          a, b = t.split("-", 2).map(&:to_i)
          lo, hi = [a, b].minmax
          next if lo < 0 || hi > 255
          extra << "#{Regexp.escape(lo.chr)}-#{Regexp.escape(hi.chr)}"
        end
      end

      @char_class_cache[spec] = "#{DEFAULT_CHAR_CLASS}#{extra.join}".freeze
    end

    def regex(raw)
      spec = raw.to_s
      return DEFAULT_REGEX if spec.empty?

      @regex_cache ||= {}
      return @regex_cache[spec] if @regex_cache.key?(spec)

      klass = char_class(spec)
      @regex_cache[spec] = /[#{klass}]/
    rescue RegexpError
      DEFAULT_REGEX
    end
  end
end
