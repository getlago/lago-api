# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::CatalogPlans::CreatedService do
  subject(:webhook_service) { described_class.new(object: catalog_plan) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "catalog_plan.created", "catalog_plan", {
      "code" => String,
      "name" => String,
      "currency" => String
    }
  end
end
