# frozen_string_literal: true

module X402
  module Chain
    class Error < StandardError; end

    class UnreachableError < Error; end

    class UnreadablePaymentError < Error; end

    class InconclusiveError < Error; end
  end
end
