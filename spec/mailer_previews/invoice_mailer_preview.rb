# frozen_string_literal: true

class InvoiceMailerPreview < BasePreview
  def finalized
    invoice = FactoryBot.create(:invoice, :with_file, {
      fees_amount_cents: 121_49,
      total_amount_cents: 1000_00,
    })

    InvoiceMailer.with(invoice:).finalized
  end
end
