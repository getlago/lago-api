# frozen_string_literal: true

require "async"
require "async/semaphore"

module Lago
  module Fibers
    def self.concurrency
      ENV.fetch("LAGO_FIBER_CONCURRENCY", "1").to_i
    end

    def self.map(items)
      return items.map { |i| yield i } if concurrency <= 1

      Sync do
        semaphore = Async::Semaphore.new(concurrency)
        tasks = items.map { |item| semaphore.async { yield item } }
        tasks.map(&:wait)
      end
    end
  end
end
