# frozen_string_literal: true

module CatalogWallets
  class ThresholdTopUpService < BaseService
    Result = BaseResult

    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      result
    end

    private

    attr_reader :wallet
  end
end
