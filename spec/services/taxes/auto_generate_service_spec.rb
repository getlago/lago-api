# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taxes::AutoGenerateService, type: :service do
  subject(:auto_generate_service) { described_class.new(organization:) }

  let(:organization) { create(:organization) }

  describe '.call' do
    it 'creates eu taxes for organization' do
      auto_generate_service.call

      aggregate_failures do
        expect(Tax.count).to eq(46) # EU taxes + 2 defaults
      end
    end
  end
end
