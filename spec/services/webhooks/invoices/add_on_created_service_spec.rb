# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::AddOnCreatedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.add_on_added", "invoice"
  end
end
