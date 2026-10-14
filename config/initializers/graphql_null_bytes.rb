# frozen_string_literal: true

# Postgres rejects strings containing a null byte. GraphQL decodes \u0000 escapes in string
# literals itself, after the request is read, so String, ID and JSON arguments are cleaned when
# they are coerced (every string nested in a JSON argument, keys included). This covers inline
# literals and variables alike. An escaped backslash such as "a\\u0000" is the text a\u0000,
# holds no null byte and stays unchanged.
module GraphqlNullByteStripping
  def coerce_input(value, ctx)
    NullByteGuard.strip(super)
  end
end

GraphQL::Types::String.singleton_class.prepend(GraphqlNullByteStripping)
GraphQL::Types::ID.singleton_class.prepend(GraphqlNullByteStripping)
GraphQL::Types::JSON.singleton_class.prepend(GraphqlNullByteStripping)
