# frozen_string_literal: true

module Charges
  class UpdateChildrenJob < ApplicationJob
    queue_as :default

    def perform(params:, old_parent_attrs:, old_parent_filters_attrs:)
      charge = Charge.find_by(id: old_parent_attrs["id"])
      Charges::UpdateChildrenService.call!(charge:, params:, old_parent_attrs:, old_parent_filters_attrs: )
    end
  end
end
