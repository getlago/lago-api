# frozen_string_literal: true

module Agents
  class ClaimMailer < ApplicationMailer
    def verification
      @claim = Agents::Claim.find_by(id: params[:claim_id])
      return unless deliverable?

      @organization = @claim.organization
      @storefront = @claim.registration.storefront
      @show_lago_logo = !@organization.remove_branding_watermark_enabled?
      billing_entity = customer.billing_entity

      # Issued here, inside the mailer action, so no job argument or mailer param ever holds the code.
      @code = Agents::Claims::IssueVerificationCodeService.call!(claim: @claim).code

      I18n.with_locale(:en) do
        mail(
          to: @claim.email,
          from: email_address_with_name(billing_entity.from_email_address.presence || ENV["LAGO_FROM_EMAIL"], billing_entity.name),
          reply_to: billing_entity.email.present? ? email_address_with_name(billing_entity.email, billing_entity.name) : nil,
          subject: I18n.t("email.agent_claim.verification.subject", storefront_name: @storefront.name)
        )
      end
    rescue ActiveRecord::RecordNotFound
      # The agent asked for a new code between the start and this delivery.
      nil
    end

    private

    # The claim may have been replaced, verified or revoked since the mail was queued.
    def deliverable?
      @claim&.started? &&
        @claim.email.present? &&
        @claim.registration.active? &&
        customer.present? &&
        @claim.organization.agent_storefront_enabled?
    end

    def customer
      @customer ||= @claim.registration.customer
    end
  end
end
