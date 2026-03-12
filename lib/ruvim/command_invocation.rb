# frozen_string_literal: true

module RuVim
  class CommandInvocation
    attr_accessor :id, :argv, :kwargs, :count, :bang, :raw_keys

    def initialize(id:, argv: [], kwargs: {}, count: nil, bang: false, raw_keys: nil)
      @id = id
      @argv = argv
      @kwargs = kwargs
      @count = count
      @bang = bang
      @raw_keys = raw_keys
    end
  end
end
