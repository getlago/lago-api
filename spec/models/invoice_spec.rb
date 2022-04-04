# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoice, type: :model do
  describe 'validate_date_bounds' do
    let(:invoice) do
      build(:invoice, from_date: Time.zone.now - 2.days, to_date: Time.zone.now)
    end

    it 'ensures from_date is before to_date' do
      expect(invoice).to be_valid
    end

    context 'when from_date is after to_date' do
      let(:invoice) do
        build(:invoice, from_date: Time.zone.now + 2.days, to_date: Time.zone.now)
      end

      it 'ensures from_date is before to_date' do
        expect(invoice).not_to be_valid
      end
    end
  end
end
