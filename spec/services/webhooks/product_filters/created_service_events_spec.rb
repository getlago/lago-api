# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ProductFilters::CreatedService do
  let(:organization) { create(:organization) }
  let(:product_filter) { create(:product_filter, organization:) }

  before { allow(product_filter.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::ProductFilters::CreatedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it_behaves_like "creates webhook", "product_filter.created", "product_filter", {"code" => String}
  end

  describe Webhooks::ProductFilters::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it_behaves_like "creates webhook", "product_filter.updated", "product_filter", {"code" => String}
  end

  describe Webhooks::ProductFilters::DeletedService do
    subject(:webhook_service) { described_class.new(object: product_filter) }

    it_behaves_like "creates webhook", "product_filter.deleted", "product_filter", {"code" => String}
  end
end
