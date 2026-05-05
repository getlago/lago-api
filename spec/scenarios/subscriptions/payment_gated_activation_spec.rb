# frozen_string_literal: true

require "rails_helper"

describe "Payment Gated Subscription Activation Scenarios" do
  describe "gated subscription with pending VIES check" do
    it "completes the flow: gated → VIES pending → VIES resolved → payment → activation" do
      pending "requires CreateService integration with ActivateService gated path (PR #5370)"

      # 1. Create subscription with payment gating + customer has pending VIES check
      # 2. Invoice created as open, tax_status: pending (VIES blocks tax calculation)
      # 3. No payment triggered yet (can't pay without taxes)
      # 4. VIES resolves → ViesCheckJob picks up the open invoice
      # 5. FinalizePendingViesInvoiceService applies taxes, triggers payment only
      # 6. Payment succeeds → subscription activates, invoice finalized
      raise "not implemented"
    end
  end

  describe "gated subscription with provider tax failure" do
    it "completes the flow: gated → tax failure → retry → payment → activation" do
      pending "requires CreateService integration with ActivateService gated path (PR #5370)"

      # 1. Create subscription with payment gating + customer has tax provider
      # 2. Invoice created as open, tax provider fails → invoice status: failed
      # 3. User retries → RetryService sets status back to open (not pending)
      # 4. PullTaxesAndApplyService succeeds → triggers payment only
      # 5. Payment succeeds → subscription activates, invoice finalized
      raise "not implemented"
    end
  end
end
