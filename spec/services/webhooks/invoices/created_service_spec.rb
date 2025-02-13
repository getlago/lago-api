# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::CreatedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  before do
    create_list(:fee, 4, invoice:)
    create_list(:credit, 4, invoice:)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.created", "invoice", {"fees" => Array, "credits" => Array}
  end
end
