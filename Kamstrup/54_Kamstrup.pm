##############################################################################
#
#     54_Kamstrup.pm
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#  
#  54_Kamstrup (c) Johannes Viegener / https://github.com/viegener/Telegram-fhem
#  
#  $Id:$
#  
##############################################################################
# 0.0 2017-0416 Started
#   Inital Version to communicate with Arduino with Kamstrup smartmeter firmware54_Kamstrup
#   
#   
#   
#   
##############################################
##############################################
### TODO
#   
#   
#
##############################################
##############################################
##############################################
##############################################
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Encode qw( decode encode );
use Data::Dumper; 

#########################
# Forward declaration

sub Kamstrup_Read($@);
sub Kamstrup_Write($$$);
sub Kamstrup_ReadAnswer($$);
sub Kamstrup_Ready($);

#########################
# Globals

##############################################################################
##############################################################################
##
## Module operation
##
##############################################################################
##############################################################################

sub
Kamstrup_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}       = "Kamstrup_Read";
  $hash->{WriteFn}      = "Kamstrup_Write";
  $hash->{ReadyFn}      = "Kamstrup_Ready";
  $hash->{UndefFn}      = "Kamstrup_Undef";
  $hash->{ShutdownFn}   = "Kamstrup_Undef";
  $hash->{ReadAnswerFn} = "Kamstrup_ReadAnswer";
  $hash->{NotifyFn}     = "Kamstrup_Notify"; 
   
  $hash->{AttrFn}     = "Kamstrup_Attr";
  $hash->{AttrList}   = "initCommands:textField disable:0,1 ".$readingFnAttributes;           

  $hash->{TIMEOUT} = 1;      # might be better?      0.5;       
                        
# Normal devices
  $hash->{DefFn}   = "Kamstrup_Define";
  $hash->{SetFn}   = "Kamstrup_Set";
  $hash->{GetFn}   = "Kamstrup_Get";
}


#####################################
sub
Kamstrup_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    return "wrong syntax: define <name> Kamstrup hostname:23";
  }

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{Clients} = ":KAMSTRUP:";
  my %matchList = ( "1:KAMSTRUP" => ".*" );
  $hash->{MatchList} = \%matchList;

  Kamstrup_Disconnect($hash);
  $hash->{DeviceName} = $dev;

  return undef if($dev eq "none"); # DEBUGGING
  
  my $ret;
  if( $init_done ) {
    Kamstrup_Disconnect($hash);
    $ret = Kamstrup_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }    
  return $ret;
}

#####################################
sub
Kamstrup_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my %sets = ("raw"=>"textField", "cmd"=>"textField", "disconnect"=>undef, "reopen"=>undef );

  my $numberOfArgs  = int(@a); 

  return "set $name needs at least one parameter" if($numberOfArgs < 1);

  my $type = shift @a;
  $numberOfArgs--; 

  my $ret = undef; 

  return "Unknown argument $type, choose one of " . join(" ", sort keys %sets) if (!exists($sets{$type}));

  if($type eq "cmd") {
    my $cmd = join(" ", @a );
    $ret = Kamstrup_SendCommand($hash,$cmd, 1);
  } elsif($type eq "raw") {
    my $cmd = "w ".join(" ", @a );
    $ret = Kamstrup_SendCommand($hash,$cmd, 1);
  } elsif($type eq "reopen") {
    Kamstrup_Disconnect($hash);
    delete $hash->{DevIoJustClosed} if($hash->{DevIoJustClosed});   
    delete($hash->{NEXT_OPEN}); # needed ? - can this ever occur
    return Kamstrup_Connect( $hash, 1 );
  } elsif($type eq "disconnect") {
    Kamstrup_Disconnect($hash);
    DevIo_setStates($hash, "disconnected"); 
      #    DevIo_Disconnected($hash);
#    delete $hash->{DevIoJustClosed} if($hash->{DevIoJustClosed});
  }

  if ( ! defined( $ret ) ) {
    Log3 $name, 4, "Kamstrup_Set $name: $type done succesful: ";
  } else {
    Log3 $name, 1, "Kamstrup_Set $name: $type failed with :$ret: ";
  } 
  return $ret;
}

#####################################
sub
Kamstrup_Get($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my %gets = ("register"=>"textField", "_register"=>"textField", "queue"=>undef );

  my $numberOfArgs  = int(@a); 

  return "set $name needs at least one parameter" if($numberOfArgs < 1);

  my $type = shift @a;
  $numberOfArgs--; 

  my $ret = undef; 

  return "Unknown argument $type, choose one of " . join(" ", sort keys %gets) if (!exists($gets{$type}));

  if( ($type =~ /.?register/ )  ) {
    my $cmd = "r ".join(" ", @a );
    $ret = Kamstrup_SendCommand($hash,$cmd, 1);
  } elsif( ($type eq "queue")  ) {
    my $cmd = "g ";
    $ret = Kamstrup_SendCommand($hash,$cmd, 1);
  }

  if ( ! defined( $ret ) ) {
    Log3 $name, 4, "Kamstrup_Set $name: $type done succesful: ";
  } else {
    Log3 $name, 1, "Kamstrup_Set $name: $type failed with :$ret: ";
  } 
  return $ret;
}

##############################
# attr function for setting fhem attributes for the device
sub Kamstrup_Attr(@) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  Log3 $name, 4, "Kamstrup_Attr $name: called ";

  return "\"Kamstrup_Attr: \" $name does not exist" if (!defined($hash));

  if (defined($aVal)) {
    Log3 $name, 4, "Kamstrup_Attr $name: $cmd  on $aName to $aVal";
  } else {
    Log3 $name, 4, "Kamstrup_Attr $name: $cmd  on $aName to <undef>";
  }
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  if ($cmd eq "set") {
    if ($aName eq 'disable') {
      if($aVal eq "1") {
        Kamstrup_Disconnect($hash);
        DevIo_setStates($hash, "disabled"); 
      } else {
        if($hash->{READINGS}{state}{VAL} eq "disabled") {
          DevIo_setStates($hash, "disconnected"); 
          InternalTimer(gettimeofday()+1, "Kamstrup_Connect", $hash, 0);
        }
      }
    }
    
    $_[3] = $aVal;
  
  }

  return undef;
}

  
######################################
sub Kamstrup_IsConnected($)
{
  my $hash = shift;
#  stacktrace();
#  Debug "Name : ".$hash->{NAME};
#  Debug "FD: ".((exists($hash->{FD}))?"def":"undef");
#  Debug "TCPDev: ".((defined($hash->{TCPDev}))?"def":"undef");

  return 0 if(!exists($hash->{FD}));
  if(!defined($hash->{TCPDev})) {
    Kamstrup_Disconnect($_[0]);
    return 0;
  }
  return 1;
}
  
######################################
sub Kamstrup_Disconnect($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  Log3 $name, 4, "Kamstrup_Disconnect: $name";
  DevIo_CloseDev($hash);
} 

######################################
sub Kamstrup_Connect($;$) {
  my ($hash, $mode) = @_;
  my $name = $hash->{NAME};
 
  my $ret;

  $mode = 0 if!($mode);

  return undef if(Kamstrup_IsConnected($hash));
  
#  Debug "NEXT_OPEN: $name".((defined($hash->{NEXT_OPEN}))?time()-$hash->{NEXT_OPEN}:"undef");

  if(!IsDisabled($name)) {
    # undefined means timeout / 0 means failed / 1 means ok
    if ( DevIo_OpenDev($hash, $mode, "Kamstrup_DoInit") ) {
      if(!Kamstrup_IsConnected($hash)) {
        $ret = "Kamstrup_Connect: Could not connect :".$name;
        Log3 $hash, 2, $ret;
      }
    }
  }
 return $ret;
}
   
#####################################
sub
Kamstrup_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if( IsDisabled($name) > 0 ) {
    readingsSingleUpdate($hash, 'state', 'disabled', 1 ) if( ReadingsVal($name,'state','' ) ne 'disabled' );
    return undef;
  }

  Kamstrup_Connect($hash);

  return undef;
}    
#####################################
sub
Kamstrup_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  my $ret = undef;
  
  ### send init commands
  my $initCmds = AttrVal( $name, "initCommands", undef ); 
    
  Log3 $name, 3, "Kamstrup_DoInit $name: Execute initCommands :".(defined($initCmds)?$initCmds:"<undef>").":";

  
  ## ??? quick hack send on init always page 0 twice to ensure proper start
  # Send command handles replaceSetMagic and splitting
  $ret = Kamstrup_SendCommand( $hash, "h", 0 );

  # Send command handles replaceSetMagic and splitting
  $ret = Kamstrup_SendCommand( $hash, $initCmds, 0 ) if ( defined( $initCmds ) );

  return $ret;
}

#####################################
sub
Kamstrup_Undef($@)
{
  my ($hash, $arg) = @_;
  ### ??? send finish commands
  Kamstrup_Disconnect($hash);
  return undef;
}

#####################################
sub
Kamstrup_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  $msg = sprintf("%s03%04x%s%s", $fn, length($msg)/2+8,
           $hash->{HANDLE} ?  $hash->{HANDLE} : "00000000", $msg);
  DevIo_SimpleWrite($hash, $msg, 1);
}

#####################################
sub
Kamstrup_SendCommand($$$)
{
  my ($hash,$msg,$answer) = @_;
  my $name = $hash->{NAME};
  my @ret; 
  
  Log3 $name, 4, "Kamstrup_SendCommand $name: send commands :".$msg.": ";

  if ( defined( ReadingsVal($name,"cmdResult",undef) ) ) {
    $hash->{READINGS}{old1}{VAL} = $hash->{READINGS}{cmdResult}{VAL};
    $hash->{READINGS}{old1}{TIME} = $hash->{READINGS}{cmdResult}{TIME};
  }
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "cmdSent", $msg);        
  readingsBulkUpdate($hash, "cmdResult", "" );        
  readingsEndUpdate($hash, 1);
    
  # First replace any magics
  my %dummy; 
  my @msgList = split(";", $msg);
  my $singleMsg;
  my $lret; # currently always empty
  while(defined($singleMsg = shift @msgList)) {
    $msg =~ s/^\s+|\s+$//g;

    Log3 $name, 4, "Kamstrup_SendCommand $name: send command :".$msg.": ";

    DevIo_SimpleWrite($hash, $msg."\r\n", 0);
    
    push(@ret, $lret) if(defined($lret));
  }

  return join("\n", @ret) if(@ret);
  return undef; 
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
Kamstrup_Read($@)
{
  my ($hash, $local, $isCmd) = @_;

  my $buf = ($local ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

###  $buf = unpack('H*', $buf);
  my $data = ($hash->{PARTIAL} ? $hash->{PARTIAL} : "");

  # drop old data
  if($data) {
    $data = "" if(gettimeofday() - $hash->{READ_TS} > 5);
    delete($hash->{READ_TS});
  }
  
  Log3 $name, 5, "Kamstrup/RAW: $data/$buf";
  $data .= $buf;
  
  if ( index($data,"\n") != -1 ) {
#    Debug "Found eol :".$data.":";
    my $cmd = ReadingsVal($name,"cmdSent",undef);
    if ( $data =~ /^$cmd\r\n(.*)/s ) {
      $data = $1;
    }
  }
  
  if ( index($data,"\n") != -1 ) {
    my $read = ReadingsVal($name,"cmdResult",undef);
    if ( ReadingsAge($name,"cmdResult",3600) > 60 ) {
      $read = "";
    }
    
    $read .= $data;
    $data = "";    
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "cmdResult", $read );        
    readingsEndUpdate($hash, 1);
  }
  
  $hash->{PARTIAL} = $data;
  $hash->{READ_TS} = gettimeofday() if($data);

  my $ret;

  return $ret if(defined($local));
  return undef;
}

#####################################
sub
Kamstrup_Ready($)
{
  my ($hash) = @_;

#  Debug "Name : ".$hash->{NAME};
#  stacktrace();
  
  return Kamstrup_Connect( $hash, 1 ) if($hash->{STATE} eq "disconnected");
  return 0;
}

##############################################################################
##############################################################################
##
## Helper
##
##############################################################################
##############################################################################



1;

=pod
=item summary    interact with Kamstrup Smartmeter 382Lx3 
=item summary_DE interagiert mit Kamstrup Smartmeter 382Lx3
=begin html

<a name="Kamstrup"></a>
<h3>Kamstrup</h3>
<ul>

  This module connects remotely to an Arduino running a special Kamstrup smartmeter reader software (e.g. connected through a ESP8266 or similar serial to network connection)
  
  <br><br>
  <a name="Kamstrupdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Kamstrup &lt;hostname/ip&gt;:23 </code>
    <br><br>
    Defines a Kamstrup device on the given hostname / ip and port (should be port 23/telnetport normally)
    <br><br>
    Example: <code>define counter Kamstrup 10.0.0.1:23</code><br>
    <br>
  </ul>
  <br><br>   
  
  <a name="Kamstrupset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;what&gt; [&lt;value&gt;]</code>
    <br><br>
    where &lt;what&gt; / &lt;value&gt; is one of

  <br><br>
    <li><code>raw &lt;nextion command&gt;</code><br>Sends the given raw message to the nextion display. The supported commands are described with the Nextion displays: <a href="http://wiki.iteadstudio.com/Nextion_Instruction_Set">http://wiki.iteadstudio.com/Nextion_Instruction_Set</a>
    <br>
    Examples:<br>
      <dl>
        <dt><code>set nxt raw page 0</code></dt>
          <dd> switch the display to page 0 <br> </dd>
        <dt><code>set nxt raw b0.txt</code></dt>
          <dd> get the text for button 0 <br> </dd>
      <dl>
    </li>
    <li><code>cmd &lt;nextion command&gt;</code><br>same as raw
    </li>
    <li><code>page &lt;0 - 9&gt;</code><br>set the page number given as new page on the nextion display.
    </li>
    <li><code>pageCmd &lt;one or multiple page numbers separated by ,&gt; &lt;cmds&gt;</code><br>Execute the given commands if the current page on the screen is in the list given as page number.
    </li>
  </ul>

  <br><br>

  <a name="Kamstrupattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li><code>hasSendMe &lt;0 or 1&gt;</code><br>Specify if the display definition on the Nextion display is using the "send me" checkbox to send current page on page changes. This will then change the reading currentPage accordingly
    </li> 

    <li><code>initCommands &lt;series of commands&gt;</code><br>Display will be initialized with these commands when the connection to the device is established (or reconnected). Set logic for executing perl or getting readings can be used. Multiple commands will be separated by ;<br>
    Example<br>
    &nbsp;&nbsp;<code>t1.txt="Hallo";p1.val=1;</code>
    </li> 
    
    <li><code>initPage1 &lt;series of commands&gt;</code> to <code>initPage9 &lt;series of commands&gt;</code><br>When the corresponding page number will be displayed the given commands will be sent to the display. See also initCommands.<br>
    Example<br>
    &nbsp;&nbsp;<code>t1.txt="Hallo";p1.val=1;</code>
    </li> 

    <li><code>expectAnswer &lt;1 or 0&gt;</code><br>Specify if an answer from display is expected. If set to zero no answer is expected at any time on a command.
    </li> 

  </ul>

  <br><br>


    <a name="Kamstrupreadings"></a>
  <b>Readings</b>
  <ul>
    <li><code>received &lt;Hex values of the last received message from the display&gt;</code><br> The message is converted in hex values (old messages are stored in the readings old1 ... old5). Example for a message is <code>H65(e) H00 H04 H00</code> </li> 
    
    <li><code>rectext &lt;text or empty&gt;</code><br> Translating the received message into text form if possible. Beside predefined data that is sent from the display on specific changes, custom values can be sent in the form <code>$name=value</code>. This can be sent by statements in the Nextion display event code <br>
      <code>print "$bt0="<br>
            get bt0.val</code>
    </li> 
    
    <li><code>currentPage &lt;page number on the display&gt;</code><br> Shows the number of the UI screen as configured on the Nextion display that is currently shown.<br>This is only valid if the attribute <code>hasSendMe</code> is set to 1 and used also in the display definition of the Nextion.</li> 
    
    <li><code>cmdSent &lt;cmd&gt;</code><br> Last cmd sent to the Nextion Display </li> 
    <li><code>cmdResult &lt;result text&gt;</code><br> Result of the last cmd sent to the display (or empty)</li> 
    
    
  </ul> 

  <br><br>   
</ul>




=end html
=cut 