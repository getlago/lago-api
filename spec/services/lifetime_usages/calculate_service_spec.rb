# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::CalculateService, type: :service do
  subject(:service) { described_class.new(lifetime_usage: lifetime_usage) }

  let(:lifetime_usage) { create(:lifetime_usage, subscription:, recalculate_current_usage:, recalculate_invoiced_usage:) }
  let(:recalculate_current_usage) { true }
  let(:recalculate_invoiced_usage) { true }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:customer) { create(:customer) }
  let(:invoices) { create_list(:invoice, 2, :finalized, subscription:, amounts_cents: [1000, 2000]) }

  describe '#call' do
    context "without previous invoices" do
      it "recalculates the invoiced_usage as zero" do
        result = service.call

        expect(result.lifetime_usage.invoiced_usage_amount_cents).to be_zero
      end
    end
  end
end
