# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Fees::PayInAdvanceCreatedService do
  subject(:webhook_service) { described_class.new(object: fee) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:fee) { create(:fee, customer:, subscription:) }

  describe ".call" do
    it_behaves_like "creates webhook", "fee.created", "fee", {"amount_cents" => Integer}
  end
end
