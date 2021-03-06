#同步过程中有key过期导致主从不一致(从节点key更少)
start_server {tags {"repl"}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set num 100000
    set clients 50
    start_server {} {
        set slave [srv 0 client]
        test {MASTER and SLAVE consistency after sync during key expiring} {
            set clist [start_bg_complex_data_list $master_host $master_port $num $clients sexpire]
            after 10000

            $slave slaveof [srv -1 host] [srv -1 port]
            wait_for_condition 200 100 {
                [s master_link_status] eq {up}
            } else {
                stop_bg_client_list $clist
                fail "Replication not started."
            }
            stop_bg_client_list $clist
            foreach key [$master keys *] {
                wait_for_condition 10 1 {
                    [$master exists $key] eq [$slave exists $key]
                } else {
                    fail "$key not identical: [$master exists $key] : [$slave exists $key]"
                }
            }
        }
    }
}

start_server {tags {"repl"}} {
    set master [srv 0 client]
    start_server {} {
        set slave [srv 0 client]
        test {MASTER and SLAVE consistency with single key expire} {
            $slave slaveof [srv -1 host] [srv -1 port]
            wait_for_condition 200 100 {
                [s master_link_status] eq {up}
            } else {
                fail "Replication not started."
            }
            $master set foo bar
            $master expire foo 1
            wait_for_condition 10 100 {
                [ $slave ttl foo ] > 0 &&
                [ $slave exists foo ] == 1
            } else {
                fail "key with expire time propogate to slave"
            }
            after 2000

            set oldmaxmemory [lindex [ $master config get maxmemory ] 1]
            wait_for_condition 10 100 {
                [ $master exists foo ] == 0 &&
                [ $slave exists foo ] == 0
            } else {
                fail "key in master and slave not identical"
            }
        }

        test {MASTER and SLAVE consistency with expire} {
            if {$::accurate} {set numops 20000} else {set numops 5000}
            set keyslist [ createComplexDataset $master $numops useexpire ]
            after 4000 ;# Make sure everything expired before taking the digest

            set oldmaxmemory [lindex [ $master config get maxmemory ] 1]
            foreach key $keyslist {
                wait_for_condition 50 100 {
                    [ $master exists $key ] eq [ $slave exists $key ]
                } else {
                    fail "key:$key in master and slave not identical [ $master exists $key ] [ $slave exists $key ]"
                }
            }
            after 1000 ;# Wait another second. Now everything should be fine.
            $master config set maxmemory 0 ;# load all keys to redis
            assert_equal [r debug digest] [r -1 debug digest]
            compare_debug_digest
            $master config set maxmemory $oldmaxmemory
        }
    }
}

# not support eval
#start_server {tags {"repl"}} {
#    start_server {} {
#        test {First server should have role slave after SLAVEOF} {
#            r -1 slaveof [srv 0 host] [srv 0 port]
#            wait_for_condition 50 100 {
#                [s -1 master_link_status] eq {up}
#            } else {
#                fail "Replication not started."
#            }
#        }
#
#        set numops 20000 ;# Enough to trigger the Script Cache LRU eviction.
#
#        # While we are at it, enable AOF to test it will be consistent as well
#        # after the test.
#        r config set appendonly yes
#
#        test {MASTER and SLAVE consistency with EVALSHA replication} {
#            array set oldsha {}
#            for {set j 0} {$j < $numops} {incr j} {
#                set key "key:$j"
#                # Make sure to create scripts that have different SHA1s
#                set script "return redis.call('incr','$key')"
#                set sha1 [r eval "return redis.sha1hex(\"$script\")" 0]
#                set oldsha($j) $sha1
#                r eval $script 0
#                set res [r evalsha $sha1 0]
#                assert {$res == 2}
#                # Additionally call one of the old scripts as well, at random.
#                set res [r evalsha $oldsha([randomInt $j]) 0]
#                assert {$res > 2}
#
#                # Trigger an AOF rewrite while we are half-way, this also
#                # forces the flush of the script cache, and we will cover
#                # more code as a result.
#                if {$j == $numops / 2} {
#                    catch {r bgrewriteaof}
#                }
#            }
#
#            wait_for_condition 50 100 {
#                [r dbsize] == $numops &&
#                [r -1 dbsize] == $numops &&
#                [r debug digest] eq [r -1 debug digest]
#            } else {
#                set csv1 [csvdump r]
#                set csv2 [csvdump {r -1}]
#                set fd [open /tmp/repldump1.txt w]
#                puts -nonewline $fd $csv1
#                close $fd
#                set fd [open /tmp/repldump2.txt w]
#                puts -nonewline $fd $csv2
#                close $fd
#                puts "Master - Slave inconsistency"
#                puts "Run diff -u against /tmp/repldump*.txt for more info"
#
#            }
#
#            set old_digest [r debug digest]
#            r config set appendonly no
#            r debug loadaof
#            set new_digest [r debug digest]
#            assert {$old_digest eq $new_digest}
#        }
#    }
#}
