# frozen_string_literal: true

class RenameCreditNoteRefundFailureEventType < ActiveRecord::Migration[8.1]
  OLD_NAME = "credit_note.provider_refund_failure"
  NEW_NAME = "credit_note.refund_failure"

  def up
    rename_event_type(OLD_NAME, NEW_NAME)
  end

  def down
    rename_event_type(NEW_NAME, OLD_NAME)
  end

  private

  def rename_event_type(from, to)
    WebhookEndpoint.unscoped
      .where("? = ANY(event_types)", from)
      .in_batches(of: 1000)
      .update_all(["event_types = array_replace(event_types, ?, ?), updated_at = ?", from, to, Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end
end
