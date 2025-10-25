ExUnit.start()
Logger.configure(level: :info)

# Load support helpers
Code.require_file("support/sql_case.ex", __DIR__)
