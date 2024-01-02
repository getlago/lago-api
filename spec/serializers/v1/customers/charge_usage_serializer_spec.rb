# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Customers::ChargeUsageSerializer do
  subject(:serializer) { described_class.new(nil) }

  describe '#groups' do
    subject(:serializer_groups) { serializer.__send__(:groups, fees) }

    let(:fees) { [fee1, fee2] }
    let(:group) { create(:group) }

    context 'when all fees have groups' do
      let(:fee1) { create(:fee, group:) }
      let(:fee2) { create(:fee, group:) }

      let(:groups) do
        [
          {
            lago_id: fee2.group.id,
            key: fee2.group.key,
            value: fee2.group.value,
            units: fee2.units,
            amount_cents: fee2.amount_cents,
            events_count: fee2.events_count,
          },
          {
            lago_id: fee1.group.id,
            key: fee1.group.key,
            value: fee1.group.value,
            units: fee1.units,
            amount_cents: fee1.amount_cents,
            events_count: fee1.events_count,
          },
        ]
      end

      it 'returns groups array' do
        expect(serializer_groups).to eq(groups)
      end
    end

    context 'when one fee does not have a group' do
      let(:fee1) { create(:fee) }
      let(:fee2) { create(:fee, group:) }

      let(:groups) do
        [
          {
            lago_id: fee2.group.id,
            key: fee2.group.key,
            value: fee2.group.value,
            units: fee2.units,
            amount_cents: fee2.amount_cents,
            events_count: fee2.events_count,
          },
        ]
      end

      it 'returns groups array' do
        expect(serializer_groups).to eq(groups)
      end
    end
  end
end
