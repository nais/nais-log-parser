# coding: utf-8
require "nais/log/parser/version"
require "time"
require "json"
require "logfmt"
require "uri"

module Nais
  module Log
    module Parser

      def Parser.string_array(array)
        array.each_with_object([]) do |item, v|
          v << item.to_s
        end
      end

      def Parser.flatten_hash(hash, path = "", keep = nil)
        hash.each_with_object({}) do |(k, v), ret|
          if path == "" && !keep.nil? && k =~ keep
            ret[k] = v
          else
            key = (path + k.to_s).tr('.','_')
            if v.is_a? Hash
              ret.merge! Parser.flatten_hash(v, key.to_s + "_")
            elsif v.is_a? Array
              ret[key] = string_array(v)
            else
              ret[key] = v
            end
          end
        end
      end

      def Parser.get_keywords(str, regex)
        keywords = str.scan(regex)
        if keywords.any?
          keywords.uniq!
          keywords.size == 1 ? keywords.first : keywords
        end
      end

      def Parser.merge_json_field(record, field)
        if record.has_key?(field)
          value = record[field].strip
          if value[0].eql?('{') && value[-1].eql?('}')
            begin
              record = JSON.parse(value).merge(record)
              record.delete(field)
            rescue JSON::ParserError=>e
            end
          end
        end
        record
      end

      def Parser.remap_journald_fields(record)
        record.delete('boot_id')
        record['level'] = case record['priority']
                          when '7'
                            'Debug'
                          when '6'
                            'Info'
                          when '5'
                            'Notice'
                          when '4'
                            'Warning'
                          when '3'
                            'Error'
                          when '2'
                            'Critical'
                          when '1'
                            'Alert'
                          when '0'
                            'Emergency'
                          end
        record.delete('priority')
        if record.has_key?('syslog_facility')
          record['facility'] = case record['syslog_facility']
                               when '23'
                                 'local7'
                               when '22'
                                 'local6'
                               when '21'
                                 'local5'
                               when '20'
                                 'local4'
                               when '19'
                                 'local3'
                               when '18'
                                 'local2'
                               when '17'
                                 'local1'
                               when '16'
                                 'local0'
                               when '15'
                                 'cron'
                               when '14'
                                 'logalert'
                               when '13'
                                 'logaudit'
                               when '12'
                                 'ntp'
                               when '11'
                                 'ftp'
                               when '10'
                                 'authpriv'
                               when '9'
                                 'clock'
                               when '8'
                                 'uucp'
                               when '7'
                                 'news'
                               when '6'
                                 'lpr'
                               when '5'
                                 'syslog'
                               when '4'
                                 'auth'
                               when '3'
                                 'daemon'
                               when ''
                                 'mail'
                               when '1'
                                 'user'
                               when '0'
                                 'kern'
                               end
          record.delete('syslog_facility')
        end
        record.delete('syslog_pid')
        record.delete('syslog_timestamp')
        record.delete('syslog_raw')
        # keep record['uid']
        # keep record['gid']
        record.delete('cap_effective')
        record.delete('code_file')
        record.delete('code_line')
        record.delete('code_func')
        record.delete('coredump_environ')
        record.delete('coredump_open_fds')
        record.delete('coredump_proc_maps')
        record.delete('coredump_proc_mountinfo')
        record.delete('systemd_slice')
        record.delete('cap_effective')
        record['category'] = record.delete('transport')
        record.delete('machine_id')
        record['host'] = record.delete('hostname')
        record.delete('selinux_context')
        record.delete('stream_id')
        record['program'] = record.delete('syslog_identifier')
        # keep record['pid']
        record['command'] = record.delete('comm') if record.has_key?('comm')
        record.delete('exe')
        record.delete('cmdline')
        # keep record['interface']
        record.delete('systemd_cgroup')
        record.delete('systemd_unit')
        record.delete('systemd_invocation_id')
        # keep record['message']
        record.delete('source_monotonic_timestamp')
        ts = record.delete('source_realtime_timestamp')
        unless ts.nil?
          record['timestamp'] = Time.at(ts[0..9].to_i, ts[10..16].to_i).utc.iso8601(6)
        end
        record
      end

      def Parser.remap_elasticsearch_fields(time, record)
        record["received_at"] = Time.new.iso8601(9)
        unless record.has_key?("@timestamp")
          record["@timestamp"] = record.delete("timestamp") || record.delete("time") || record.delete("ts") || Time.at(time).iso8601(9)
        end
        unless record.has_key?("message")
          record["message"] = record.delete("msg") || record.delete("log")
        end
        record.delete('log')
        record
      end

      def Parser.remap_java_fields(record)
        record["thread"] = record.delete("thread_name") if record.has_key?("thread_name")
        record["component"] = record.delete("logger_name") if record.has_key?("logger_name")
        if record.has_key?("level")
          if record['level'].is_a?(String)
            record['level'].capitalize!
            record['level'] = 'Warning' if record['level'] == 'Warn'
          else
            record['x_level'] = record.delete('level')
          end
        end
        record.delete("level_value")
        record.delete("ndc")
        record.delete("source_host")
        if record.has_key?('exception')
          record['stack_trace'] = record['exception']['stacktrace'] if record['exception'].has_key?('stacktrace')
          record.delete('exception')
        end
        if record.has_key?('mdc')
          record['mdc'].each{|k,v|
            record[k] = record['mdc'][k]
          }
          record.delete('mdc')
        end
        record
      end

      # remap fields from https://github.com/inconshreveable/log15/
      def Parser.remap_log15(record)
        record['timestamp'] = record.delete('t') if record.has_key?('t')
        record['message'] = record.delete('msg') if record.has_key?('msg')
        record['component'] = record.delete('logger') if record.has_key?('logger')
        if record.has_key?('lvl')
          record['level'] = case record['lvl']
                            when 'dbug'
                              'Debug'
                            when 'info'
                              'Info'
                            when 'warn'
                              'Warning'
                            when 'eror'
                              'Error'
                            when 'crit'
                              'Critical'
                            end
          record.delete('lvl')
        end
        record
      end
        
      def Parser.prefix_fields(record, prefix, regex, negate = false)
        r = {}
        record.each{|k,v|
          if (!negate && k =~ regex) || (negate && k !~ regex)
            r[prefix+k] = record[k]
          else
            r[k] = record[k]
          end
        }
        r
      end

      def Parser.parse_kv(str)
        r = {}
        if !str.nil? && match = str.scan(/\b([A-Za-z]{1,20})=(?:([^\ "][^, ]*)|\"([^\"]+)\"),?/)
          match.each{|m|
            r[m[0]] = m[1].nil? ? m[2] : m[1]
          }
        end
        return r.empty? ? nil : r
      end

      def Parser.parse_uri(str)
        r = {}
        unless str.nil?
          i = str.index('?')
          if i.nil?
            r['path'] = URI.decode(str)
          else
            if i != 0
              r['path'] = URI.decode(str[0,i])
            end
            if i+1 < str.length
              query = str[i+1, str.length]
              kv = {}
              query.scan(/([^=&]+)=([^&]+)/) do |k,v|
                k.gsub!(/\+/, ' ')
                k = URI.decode(k)
                v.gsub!(/\+/, ' ')
                v = URI.decode(v)
                if kv.has_key?(k)
                  if kv[k].is_a?(Array)
                    next if kv[k].include?(v)
                    kv[k].push(v)
                  else
                    next if kv[k] == v
                    kv[k] = [kv[k], v]
                  end
                else
                  kv[k] = v
                end
              end
              r['query_params'] = kv unless kv.empty?
            end
          end
        end
        r
      end

      def Parser.parse_coredns(str)
        if !str.nil? && m = str.match(/^(\S+) \[([^\]]+?)\] (.+)$/)
          r = {}
          r['timestamp'] = m[1]
          r['level'] = m[2]
          msg = m[3]
          r['message'] = msg
          if m = msg.match(/^(\S+?):(\d+) - (\d+) \"([^\"]*)\" (\S+) (\S+) (\d+) (\d+(?:\.\d+)?)s$/)
            r['remote_ip'] = m[1]
            r['remote_port'] = m[2]
            r['query_id'] = m[3]
            r['message'] = m[4]
            r['response_code'] = m[5]
            r['flags'] = m[6].split(',')
            r['content_length'] = m[7]
            r['processing_time'] = m[8]
          end
          return r
        else
          return nil
        end
      end

      def Parser.parse_rook(str)
        if !str.nil? && m = str.match(/^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) ([IWE]) \| ([^:]+): (.+)$/)
          r = {}
          r['timestamp'] = Time.parse(m[1]).utc.iso8601(9)
          r['level'] = case m[2]
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       end
          r['component'] = m[3]
          msg = m[4]
          r['message'] = msg
          return r
        else
          return nil
        end
      end

      def Parser.parse_redis(str)
        if !str.nil? && m = str.match(/^(?:\[(\d+)\]|(\d+):([XCSM])) (\d{1,2} \S{3,} \d\d:\d\d:\d\d\.\d\d\d) ([-.*#]) (.+)/)
          r = {}
          if m[3].nil?
            r['thread'] = m[1]
          else
            r['thread'] = m[2]
            r['component'] = case m[3]
                             when 'X'
                               'sentinel'
                             when 'C'
                               'persistence'
                             when 'S'
                               'slave'
                             when 'M'
                               'master'
                             end
          end
          r['timestamp'] = Time.strptime(m[4]+'Z', "%d %b %H:%M:%S.%L%Z").utc.iso8601(3)
          r['level'] = case m[5]
                       when '.'
                         'Debug'
                       when '-'
                         'Info'
                       when '*'
                         'Info'
                       when '#'
                         'Error'
                       end
          r['message'] = m[6]
          return r
        else
          return nil
        end
      end

      def Parser.parse_accesslog(str)
        if !str.nil? && m = str.match(/^(\S+) +(?:(\S+) )?(\S+) \[([^\]]+)\] \"([^\"]*)\" (\S+) (\S+)(.*)/)
          r = {}
          r['remote_ip'] = m[1]
          r['ident'] = m[2] unless (m[2].nil? || m[2] == '-')
          r['user'] = m[3] unless m[3] == '-'
          r['timestamp'] = Time.strptime(m[4], "%d/%b/%Y:%H:%M:%S %Z").iso8601
          r['request'] = m[5]
          r['response_code'] = m[6] unless m[6] == '-'
          r['content_length'] = m[7] unless m[7] == '-'
          ext = m[8] unless m[8] == ''
          return r, ext
        else
          return nil
        end
      end

      def Parser.parse_accesslog_with_processing_time(str)
        r,ext = Parser.parse_accesslog(str)
        if !ext.nil? && m = ext.match(/^\s+(?:\"?-\"?|([0-9.]+)(?:[µm]?s))?$/u)
          r['processing_time'] = m[1] unless m[1].nil?
        end
        return r
      end

      def Parser.parse_accesslog_with_referer_useragent(str)
        r,ext = Parser.parse_accesslog(str)
        if !ext.nil? && m = ext.match(/^\s+\"([^\"]+)\" \"([^\"]+)\"$/)
          r['referer'] = m[1] unless m[1] == '-'
          r['user_agent'] = m[2] unless m[2] == '-'
        end
        return r
      end

      def Parser.parse_logrus(str)
        r = Logfmt.parse(str)
        if !r.nil? && r.has_key?('time') && r.has_key?('level') && r.has_key?('msg')
          r
        else
          nil
        end
      end

      def Parser.parse_gokit(str)
        r = Logfmt.parse(str)
        if !r.nil? && r.has_key?('ts') && r.has_key?('level') && (r.has_key?('msg') || r.has_key?('err'))
          r
        else
          nil
        end
      end

      def Parser.parse_glog(str)
        if !str.nil? && m = str.match(/^([IWEF])(\d{4} \d\d:\d\d:\d\d\.\d{6})\s+(\S+)\s([^:]+):(\d+)\]\s+(.*)/)
          r = {}
          r['level'] = case m[1]
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       when 'F'
                         'Critical'
                       end
          r['timestamp'] = Time.strptime(m[2], "%m%d %H:%M:%S.%N").utc.iso8601(9)
          r['thread'] = m[3]
          r['file'] = m[4]
          r['line'] = m[5]
          r['message'] = m[6]
          return r
        else
          return nil
        end
      end

      def Parser.parse_simple(str)
        if !str.nil? && m = str.match(/^(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[,.]\d{3,9})?) ([a-zA-Z]+) (?:\[([^\]]+)\] )?(\S+) (.*)/)
          r = {}
          r['timestamp'] = Time.parse(m[1]).utc.iso8601(9)
          r['level'] = m[2]
          r['thread'] = m[3] if !m[3].nil?
          r['component'] = m[4]
          r['message'] = m[5]
          return r
        else
          return nil
        end
      end

      # https://github.com/coreos/pkg/tree/master/capnslog
      def Parser.parse_capnslog(str)
        if !str.nil? && m = str.match(/^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{6}) ([TDNIWEC]) \| ([^:]+):\s*(.*)/)
          r = {}
          r['timestamp'] = Time.strptime(m[1], "%Y-%m-%d %H:%M:%S.%N").utc.iso8601(9)
          r['level'] = case m[2]
                       when 'T'
                         'Trace'
                       when 'D'
                         'Debug'
                       when 'N'
                         'Notice'
                       when 'I'
                         'Info'
                       when 'W'
                         'Warning'
                       when 'E'
                         'Error'
                       when 'C'
                         'Critical'
                       end
          r['component'] = m[3]
          r['message'] = m[4]
          return r
        else
          return nil
        end
      end

      def Parser.parse_influxdb(str)
        if !str.nil? && m = str.match(/^\[([^\]]+)\] (.*)$/)
          r = {}
          comp = m[1]
          msg = m[2]
          if comp == 'httpd'
            ar, ext = parse_accesslog(msg)
            unless ar.nil?
              r = ar
              r['message'] = r.delete('request')
              if !ext.nil? && m = ext.match(/^ \"([^\"]+)\" \"([^\"]+)\" ([0-9a-f-]+) (\d+)$/)
                r['referer'] = m[1] unless m[1] == '-'
                r['user_agent'] = m[2]  unless m[2] == '-'
                r['request'] = m[3] unless m[3] == '-'
                r['processing_time'] = m[4] unless m[4] == '-'
              end
            end
          end
          case comp
          when 'D'
            r['level'] = 'Debug'
          when 'I'
            r['level'] = 'Info'
          when 'W'
            r['level'] = 'Warning'
          when 'E'
            r['level'] = 'Error'
          else
            r['component'] = comp
          end
          if m = msg.match(/^(\d{4}[-\/]\d\d[-\/]\d\d)[ T](\d\d:\d\d:\d\d)Z? (.*)/)
            r['timestamp'] = Time.strptime(m[1].tr('/','-')+" "+m[2]+"+00:00", "%Y-%m-%d %H:%M:%S%Z").iso8601
            r['message'] = m[3]
          elsif r['message'].nil?
            r['message'] = msg
          end
          return r
        else
          return nil
        end
      end

      def Parser.loglevel_from_dns_response(response)
        return case response
               when 'NOERROR'
                 'Info'
               when 'NODATA'
                 'Warning'
               when 'FORMERR'
                 'Warning'
               when 'SERVFAIL'
                 'Error'
               when 'NXDOMAIN'
                 'Warning'
               when 'NOTIMP'
                 'Warning'
               when 'REFUSED'
                 'Warning'
               end
      end

      def Parser.loglevel_from_http_response(response)
        return case response.to_s[0,1]
               when '2','3'
                 'Info'
               when '4'
                 'Warning'
               when '5'
                 'Error'
               end
      end

    end
  end
end
