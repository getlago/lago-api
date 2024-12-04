# frozen_string_literal: true

module InvoiceCustomSections
  class SelectService < BaseService
    def initialize(section:, organization:)
      @section = section
      @organization = organization
      super
    end

    def call
    end

    private

    attr_reader :section, :organization
  end
end
