=begin
 Plugin: Fitbit
 Description: Grabs todays fitbit stats. See fitbit.com
 Author: Patrice Brend'amour
 Modified By: Kevin Burns

 Notes:
 1. To run this plugin you need to install the fitgem gem first:
 $ sudo gem install fitgem
 2. Afterwards you need to aquire a valid Fitbit Consumer token: http://dev.fitbit.com
 3. Upon first start, the plugin will ask you to open a URL and authorize the access to your data

=end


config = {
    'fitbit_description' => [
    'Grabs todays fitbit stats. See fitbit.com',
    'fitbit_unit_system defines the unit system used. Values: METRIC, US, UK.  (default is US)'],
    'fitbit_consumer_key' => '',
    'fitbit_consumer_secret' => '',
    'fitbit_oauth_token' => '',
    'fitbit_oauth_secret' => '',
    'fitbit_tags' => '#activities',
    'fitbit_log_water' => false,
    'fitbit_log_body_measurements' => true,
    'fitbit_log_sleep' => true,
}

$slog.register_plugin({ 'class' => 'FitbitLogger', 'config' => config })

require 'rubygems'
require 'fitgem'
require 'time'

class FitbitLogger < Slogger
    def do_log
        if @config.key?(self.class.name)
            config = @config[self.class.name]

            # Check that the user has configured the plugin
            if !config.key?('fitbit_consumer_key') || config['fitbit_consumer_secret'] == ""
                @log.warn("Fitbit has not been configured, please create an application at http://dev.fitbit.com.")
                return
            end
            else
            @log.warn("Fitbit has not been configured please edit your slogger_config file.")
            return
        end

        # ============================================================
        # Init fitgem client

        oauth_token = config['fitbit_oauth_token']
        oauth_secret = config['fitbit_oauth_secret']
        fitbit_consumer_key = config['fitbit_consumer_key']
        fitbit_consumer_secret = config['fitbit_consumer_secret']

        client = Fitgem::Client.new(:consumer_key => fitbit_consumer_key, :consumer_secret => fitbit_consumer_secret, :unit_system => config['fitbit_unit_system'])
        developMode = $options[:develop]


        # ============================================================
        # request oauth token if needed

        if  oauth_token != '' && oauth_secret != ''
            access_token = client.reconnect(oauth_token, oauth_secret)
            else
            request_token = client.request_token
            token = request_token.token
            secret = request_token.secret

            @log.info("Go to http://www.fitbit.com/oauth/authorize?oauth_token=#{token} and then enter the verifier code below")
            verifier = gets.chomp

            access_token = client.authorize(token, secret, { :oauth_verifier => verifier })
            if developMode
                @log.info("Verifier is: "+verifier)
                @log.info("Token is:    "+access_token.token)
                @log.info("Secret is:   "+access_token.secret)
            end

            config['fitbit_oauth_token'] = access_token.token;
            config['fitbit_oauth_secret'] = access_token.secret
        end

        # ============================================================
        # iterate over the days and create entries
        $i = 0
        days = $options[:timespan]
        until $i >= days  do
            currentDate = Time.now - ((60 * 60 * 24) * $i)
            timestring = currentDate.strftime('%F')

            @log.info("Logging Fitbit summary for #{timestring}")

            activities = client.activities_on_date(timestring)
            summary = activities['summary']
            steps = summary['steps']
            floors = summary['floors']
            distance = summary['distances'][0]['distance']
            distanceUnit = client.label_for_measurement(:distance, false)
            activityPoints = summary['activeScore']

            if config['fitbit_log_body_measurements']
                measurements = client.body_measurements_on_date(timestring)
                weight = measurements['body']['weight']
                fat = measurements['body']['fat']
                weightUnit = client.label_for_measurement(:weight, false)
            end
            if config['fitbit_log_water']
                water = client.water_on_date(timestring)
                waterSummary = water['summary']
                loggedWater = waterSummary['water']
                waterUnit = client.label_for_measurement(:liquids, false)
            end
            if config['fitbit_log_sleep']
                sleepData = client.sleep_on_date(timestring)
                sleepStart = sleepData['sleep'][0]['startTime'].split("T")[1][0..4]
                sleepDuration = sleepData['sleep'][0]['timeInBed']
                sleepFallAsleep = sleepData['sleep'][0]['minutesToFallAsleep']
                sleepEfficiency = sleepData['sleep'][0]['efficiency']
                sleepMinutesAsleep = sleepData['summary']['totalMinutesAsleep']
                awakeningsCount = sleepData['sleep'][0]['awakeningsCount']

                sleepDurationHour = sleepDuration / 60
                sleepDurationMinute = sleepDuration % 60
                sleepMinutesAsleepHour = sleepMinutesAsleep / 60
                sleepMinutesAsleepMinute = sleepMinutesAsleep % 60

            end



            if developMode
                @log.info("Steps: #{steps}")
                @log.info("Distance: #{distance} #{distanceUnit}")
				@log.info("Weight: #{weight} #{weightUnit}")
				@log.info("Body Fat: #{fat}%")
                @log.info{"Sleep Start: #{sleepStart}"}
                @log.info("Sleep duration: #{sleepDurationHour} Hours #{sleepDurationMinute} Minutes")
                @log.info("Minutes to Fall Asleep: #{sleepFallAsleep}")
                @log.info("Awakening Count: #{awakeningsCount}")
                @log.info("minutesAsleep: #{minutesAsleep}")
                @log.info("efficiency: #{sleepEfficiency}")
            end

            tags = config['fitbit_tags'] || ''
            tags = "\n\n#{tags}\n" unless tags == ''

            output = "**Steps:** #{steps}\n**Distance:** #{distance} #{distanceUnit}\n\n"

            if config['fitbit_log_body_measurements']
                output += "**Weight:** #{weight} #{weightUnit}\n**Body Fat:** #{fat}%\n\n"
            end
            if config['fitbit_log_water']
            	output += "**Water Intake:** #{loggedWater} #{waterUnit}\n"
            end

            if config['fitbit_log_sleep']
                output += "**Sleep Start:** #{sleepStart}\n"
                output += "**In Bed For:** #{sleepDurationHour} Hours #{sleepDurationMinute} Minutes\n"
                output += "**Minutes To Fall Asleep:** #{sleepFallAsleep}\n"
                output += "**Time Spent Asleep:** #{sleepMinutesAsleepHour} Hours #{sleepMinutesAsleepMinute} Minutes\n"
                output += "**Awakening Count:** #{awakeningsCount}\n"
                output += "**Sleep Efficiency:** #{sleepEfficiency}%"
            end


            # Create a journal entry
            options = {}
            options['content'] = "## Fitbit - Summary for #{currentDate.strftime(@date_format)}\n\n#{output}#{tags}"
            options['datestamp'] = currentDate.utc.iso8601
            sl = DayOne.new
            sl.to_dayone(options)
            $i += 1
        end
        return config
    end
end
