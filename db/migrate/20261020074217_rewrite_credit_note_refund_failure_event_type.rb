# frozen_string_literal: true

# Pods of the previous release could store the former name after the first rewrite ran.
class RewriteCreditNoteRefundFailureEventType < ActiveRecord::Migration[8.1]
  OLD_NAME = "credit_note.provider_refund_failure"
  NEW_NAME = "credit_note.refund_failure"

  def up
    WebhookEndpoint.unscoped
      .where("? = ANY(event_types)", OLD_NAME)
      .in_batches(of: 1000)
      .update_all(["event_types = array_replace(event_types, ?, ?), updated_at = ?", OLD_NAME, NEW_NAME, Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end

  # The previous release expects the current name as well.
  def down
  end
end
