# frozen_string_literal: true

class DocumentMailer < ApplicationMailer
  def loggable?
    true
  end

  def log(**context)
    Rails.logger.info("[EmailActivityLog] DocumentMailer#log called, created.present?=#{created.present?}, document.present?=#{document.present?}")
    super(document:, message: created, **context) if created.present? && document.present?
  end

  def created
    @created ||= create_mail
  end

  def document
  end
end
