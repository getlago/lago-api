# frozen_string_literal: true
class BasePreview < ActionMailer::Preview
  def self.call(...)
    message = nil
    ActiveRecord::Base.transaction do
      message = super(...)
      raise ActiveRecord::Rollback
    end
    message
  end
end
