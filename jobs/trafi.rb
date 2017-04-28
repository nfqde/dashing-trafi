require 'net/http'
require 'time'
require 'json'

set :trafi_api_key, 'sandbox'
set :trafi_stops, []
set :trafi_region, 'vilnius'

def map_departures_by_schedules(schedules, span, current_time)
  schedules.map do |schedule|
    schedule['Departures'].map do |departure|
      if current_time + span > departure['TimeUtc']
        nil
      else
        {
          name: schedule['Name'],
          destination: departure['Destination'],
          color: schedule['Color'],
          time: departure['TimeLocal'],
          timeUtc: departure['TimeUtc'],
          timeLabel: "in #{(departure['TimeUtc'] - current_time) / 60}m"
        }
      end
    end
  end.flatten.compact.sort { |x, y| x[:timeUtc] <=> y[:timeUtc] }
end

def fetch_departures(stops, limit)
  current_time = Time.now.to_i
  stops.map do |stop|
    uri = URI('http://api-ext.trafi.com/departures')
    params = { region: settings.trafi_region, stop_id: stop[:id], api_key: settings.trafi_api_key }
    uri.query = URI.encode_www_form(params)

    req = Net::HTTP::Get.new(uri)
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    departures = JSON.parse(res.body)

    {
      name: departures['Stop']['Name'],
      direction: departures['Stop']['Direction'],
      departures: map_departures_by_schedules(departures['Schedules'], stop[:span], current_time)[0..limit]
    }
  end
end

SCHEDULER.every '1m', first_in: '1s' do
  stops_with_departures = fetch_departures(settings.trafi_stops, 5)
  send_event('trafi', { items: stops_with_departures })
end
