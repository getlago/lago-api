# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ExpireOrderFormsJob, job: true do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:) }

  let!(:expired_order_form) do
    create(:order_form, :expired_yesterday, customer:, organization:, quote:)
  end

  let(:future_quote) { create(:quote, customer:, organization:) }
  let!(:future_order_form) do
    create(:order_form, :expiring_tomorrow, customer:, organization:, quote: future_quote)
  end

  let(:no_expiry_quote) { create(:quote, customer:, organization:) }
  let!(:no_expiry_order_form) do
    create(:order_form, customer:, organization:, quote: no_expiry_quote, expires_at: nil)
  end

  let(:already_expired_quote) { create(:quote, customer:, organization:) }
  let!(:already_expired_order_form) do
    create(:order_form, :expired, customer:, organization:, quote: already_expired_quote)
  end

  let(:voided_quote) { create(:quote, customer:, organization:) }
  let!(:voided_order_form) do
    create(:order_form, :voided, customer:, organization:, quote: voided_quote)
  end

  describe ".perform" do
    it "enqueues ExpireOrderFormJob only for generated order forms past expires_at" do
      described_class.perform_now

      expect(OrderForms::ExpireOrderFormJob)
        .to have_been_enqueued.with(expired_order_form)
      expect(OrderForms::ExpireOrderFormJob)
        .not_to have_been_enqueued.with(future_order_form)
      expect(OrderForms::ExpireOrderFormJob)
        .not_to have_been_enqueued.with(no_expiry_order_form)
      expect(OrderForms::ExpireOrderFormJob)
        .not_to have_been_enqueued.with(already_expired_order_form)
      expect(OrderForms::ExpireOrderFormJob)
        .not_to have_been_enqueued.with(voided_order_form)
    end
  end
end
