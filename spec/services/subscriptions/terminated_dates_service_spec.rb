# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::TerminatedDatesService, type: :service do
  let(:terminated_date_service) { described_class.new(subscription:, invoice:, date_service:) }
  let(:date_service) { Subscriptions::DatesService.new(subscription, billing_date, true) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, interval: :monthly) }
  let(:subscription_at) { DateTime.parse('02 Feb 2021') }
  let(:billing_date) { DateTime.parse('2022-03-07 04:20:46.011') }
  let(:started_at) { subscription_at }
  let(:invoice) { create(:invoice, organization:, customer: subscription.customer) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      invoice:,
      subscription:,
      timestamp: billing_date,
    )
  end

  before do
    invoice_subscription
  end

  describe '#call' do
    subject(:service_call) { terminated_date_service.call }

    let(:service_current_usage) { service_call.__send__(:current_usage) }

    context 'when subscription is terminated' do
      let(:subscription) do
        create(
          :subscription,
          :terminated,
          plan:,
          subscription_at:,
          billing_time: :calendar,
          started_at:,
        )
      end

      context 'when not matching invoice subscription' do
        let(:billing_date) { DateTime.parse('2022-06-01 04:20:46.011') }

        it 'returns a new dates service', :aggregate_failures do
          result = service_call

          expect(result).to be_kind_of(Subscriptions::DatesService)
          expect(service_current_usage).to be(false)
        end
      end

      context 'when matching invoice subscription' do
        let(:billing_date) { DateTime.parse('2022-03-07 04:20:46.011') }

        it 'returns a dates service', :aggregate_failures do
          result = service_call

          expect(result).to be_kind_of(Subscriptions::DatesService)
          expect(service_current_usage).to be(true)
        end
      end
    end

    context 'when subscription is not terminated' do
      let(:subscription) do
        create(
          :subscription,
          plan:,
          subscription_at:,
          billing_time: :anniversary,
          started_at:,
        )
      end

      it 'returns a dates service', :aggregate_failures do
        result = service_call

        expect(result).to be_kind_of(Subscriptions::DatesService)
        expect(service_current_usage).to be(true)
      end
    end
  end
end
