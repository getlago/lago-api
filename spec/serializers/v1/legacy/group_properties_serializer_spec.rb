# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::Legacy::GroupPropertiesSerializer do
  subject(:serializer) { described_class.new(group_properties, root_name: 'group_properties') }

  let(:group_properties) { create(:group_property) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['group_properties']['group_id']).to eq(group_properties.group.id)
      expect(result['group_properties']['invoice_display_name']).to eq(group_properties.invoice_display_name)
    end
  end
end
