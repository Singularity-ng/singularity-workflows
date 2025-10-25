[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 100,
  import_deps: [:ecto_sql],
  # Consistent formatting for multiline structures
  locals_without_parens: [
    # Ecto macros
    field: 2,
    field: 3,
    has_many: 2,
    has_many: 3,
    has_one: 2,
    has_one: 3,
    belongs_to: 2,
    belongs_to: 3,
    many_to_many: 3,
    many_to_many: 4,
    # ExUnit macros
    assert: 1,
    refute: 1,
    assert_raise: 2,
    assert_raise: 3,
    # Phoenix macros (if used)
    get: 2,
    post: 2,
    put: 2,
    patch: 2,
    delete: 2,
    assert_html: 1,
    assert_json: 1
  ]
]
