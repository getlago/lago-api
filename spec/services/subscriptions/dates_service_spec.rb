# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::DatesService, type: :service do
  subject(:date_service) { described_class.new(subscription, billing_date, false) }

  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      subscription_date: subscription_date,
      billing_time: :anniversary,
      started_at: started_at,
    )
  end

  let(:plan) { create(:plan, interval: interval, pay_in_advance: pay_in_advance) }
  let(:pay_in_advance) { false }

  let(:subscription_date) { DateTime.parse('02 Feb 2021') }
  let(:billing_date) { DateTime.parse('07 Mar 2022') }
  let(:started_at) { subscription_date }
  let(:interval) { :monthly }

  describe '#instance' do
    let(:result) { described_class.new_instance(subscription, billing_date) }

    context 'when interval is weekly' do
      let(:interval) { :weekly }

      it 'returns a weekly service instance' do
        expect(result).to be_kind_of(Subscriptions::Dates::WeeklyService)
      end
    end

    context 'when interval is monthly' do
      let(:interval) { :monthly }

      it 'returns a monthly service instance' do
        expect(result).to be_kind_of(Subscriptions::Dates::MonthlyService)
      end
    end

    context 'when interval is yearly' do
      let(:interval) { :yearly }

      it 'returns a yearly service instance' do
        expect(result).to be_kind_of(Subscriptions::Dates::YearlyService)
      end
    end

    context 'when interval is invalid' do
      let(:interval) { :weekly }

      before do
        allow(plan).to receive(:interval).and_return(:foo)
      end

      it 'raises a not implemented error' do
        expect { result }.to raise_error(NotImplementedError)

        expect(plan).to have_received(:interval)
      end
    end
  end

  describe 'from_date' do
    it 'raises a not implemented error' do
      expect { date_service.from_date }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'to_date' do
    it 'raises a not implemented error' do
      expect { date_service.to_date }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'charges_from_date' do
    it 'raises a not implemented error' do
      expect { date_service.charges_from_date }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'charges_to_date' do
    it 'raises a not implemented error' do
      expect { date_service.charges_to_date }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'next_end_of_period' do
    it 'raises a not implemented error' do
      expect { date_service.next_end_of_period }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'previous_beginning_of_period' do
    it 'raises a not implemented error' do
      expect { date_service.previous_beginning_of_period }
        .to raise_error(NotImplementedError)
    end
  end

  describe 'charges_duration_in_days' do
    it 'raises a not implemented error' do
      expect { date_service.charges_duration_in_days }
        .to raise_error(NotImplementedError)
    end
  end
end
