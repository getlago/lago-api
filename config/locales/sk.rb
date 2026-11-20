# frozen_string_literal: true

{
  sk: {
    i18n: {
      plural: {
        keys: %i[one few other],
        rule: lambda do |count|
          case count
          when 1 then :one
          when 2, 3, 4 then :few
          else :other
          end
        end
      }
    }
  }
}
