# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::DeletedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  before do
    create_list(:fee, 2, invoice:)
    create_list(:credit, 2, invoice:)
  end

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.deleted", "invoice", {"fees" => Array, "credits" => Array}
  end
end
