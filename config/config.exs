import Config

config :gps, :device, "/dev/gps0"
config :gps, :interval, 15000

config :logger,
  backends: [:console],
  utc_log: true,
  truncate: 1024

config :logger, :console,
  format: "$date $time $metadata[$level] $levelpad$message\n",
  metadata: [:module, :line]

import_config "#{Mix.env()}.exs"
