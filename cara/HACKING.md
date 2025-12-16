mix format
mix credo --strict
mix dialyzer
mix sobelow --config
MIX_ENV=test mix test
MIX_ENV=test mix coveralls.html
