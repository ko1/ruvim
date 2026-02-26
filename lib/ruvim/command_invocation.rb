module RuVim
  class CommandInvocation
    attr_accessor :id, :argv, :kwargs, :count, :bang, :raw_keys

    def initialize(id:, argv: nil, kwargs: nil, count: nil, bang: nil, raw_keys: nil)
      @id = id
      @argv = argv || []
      @kwargs = kwargs || {}
      @count = count
      @bang = !!bang
      @raw_keys = raw_keys
    end
  end
end
