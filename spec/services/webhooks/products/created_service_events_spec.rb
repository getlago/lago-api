# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Products::CreatedService do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  before { allow(product.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::Products::CreatedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it_behaves_like "creates webhook", "product.created", "product", {"code" => String}
  end

  describe Webhooks::Products::UpdatedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it_behaves_like "creates webhook", "product.updated", "product", {"code" => String}
  end

  describe Webhooks::Products::DeletedService do
    subject(:webhook_service) { described_class.new(object: product) }

    it_behaves_like "creates webhook", "product.deleted", "product", {"code" => String}
  end
end
