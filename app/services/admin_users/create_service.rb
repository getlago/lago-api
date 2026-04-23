# frozen_string_literal: true

module AdminUsers
  class CreateService < ::BaseService
    Result = BaseResult[:admin_user]

    def initialize(email:, password:, role:)
      @email = email
      @password = password
      @role = role

      super
    end

    def call
      admin_user = AdminUser.new(email: email, password: password, role: role)
      admin_user.save!

      result.admin_user = admin_user
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :email, :password, :role
  end
end
