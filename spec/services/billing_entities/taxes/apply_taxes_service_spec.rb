# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingEntities::Taxes::ApplyTaxesService do
  subject(:service) { described_class.new(billing_entity:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:tax_codes) { ['TAX_CODE_1', 'TAX_CODE_2'] }

  describe '#call' do
    context 'when tax codes exist in the organization' do
      let(:tax1) { create(:tax, organization:, code: 'TAX_CODE_1') }
      let(:tax2) { create(:tax, organization:, code: 'TAX_CODE_2') }

      before do
        tax1
        tax2
      end

      it 'creates applied taxes for the billing entity' do
        expect { service.call }.to change(billing_entity.applied_taxes, :count).by(2)
        expect(billing_entity.applied_taxes.pluck(:tax_id)).to match_array([tax1.id, tax2.id])
      end

      context "when billing_entity already have taxes applied" do
        before do
          billing_entity.applied_taxes.create!(tax: tax1)
        end

        it 'does not create duplicate applied taxes' do
          expect { service.call }.to change(billing_entity.applied_taxes, :count).by(1)
        end
      end
    end

    context 'when some tax codes do not exist in the organization' do
      let(:tax1) { create(:tax, organization:, code: 'TAX_CODE_1') }

      before { tax1 }

      it 'fails with a not_found_failure' do
        result = service.call
        expect(result.success?).to be_falsey
        expect(result.error.message).to eq('tax_not_found')
      end

      it 'does not create any applied taxes' do
        service.call
        expect(billing_entity.applied_taxes.pluck(:tax_id)).to eq([])
      end
    end
  end
end 