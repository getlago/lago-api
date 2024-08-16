# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoice::AppliedTax, type: :model do
  subject(:applied_tax) { create(:invoice_applied_tax) }

  it_behaves_like 'paper_trail traceable'

  context '#applied_on_whole_invoice?' do
    subject(:applicable_on_whole_invoice) { applied_tax.applied_on_whole_invoice? }

    context 'when applied tax represents special rule' do
      let(:applied_tax) { create(:invoice_applied_tax, tax_code: Invoice::AppliedTax::TAX_CODES_APPLICABLE_ON_WHOLE_INVOICE.sample) }

      it 'is applicable on whole invoice' do
        expect(subject).to be(true)
      end
    end

    context 'when normal applied tax' do
      it 'is not applicable on whole invoice' do
        expect(subject).to be(false)
      end
    end

  end
end
