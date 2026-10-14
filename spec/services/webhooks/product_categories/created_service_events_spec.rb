# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ProductCategories::CreatedService do
  let(:organization) { create(:organization) }
  let(:product_category) { create(:product_category, organization:) }

  before { allow(product_category.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::ProductCategories::CreatedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it_behaves_like "creates webhook", "product_category.created", "product_category", {"code" => String}
  end

  describe Webhooks::ProductCategories::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it_behaves_like "creates webhook", "product_category.updated", "product_category", {"code" => String}
  end

  describe Webhooks::ProductCategories::DeletedService do
    subject(:webhook_service) { described_class.new(object: product_category) }

    it_behaves_like "creates webhook", "product_category.deleted", "product_category", {"code" => String}
  end
end
