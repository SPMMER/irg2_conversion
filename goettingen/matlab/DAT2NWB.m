clear

mainfolder = 'C:\Users\MFeyerabend\Dropbox\IRG2_reference_data\Goettingen\single_cells\'; %fullfile(cd, '\test_cell\');
outputfolder = 'D:\output_NeuroNex_reference\'; %[cd, '\'];
fileList = dir(fullfile(mainfolder,'**\*.dat*'));
CellCounter = 0;
deleteList = dir(fullfile(outputfolder,'*Goettingen*.nwb'));

for k = 1 : length(deleteList)
  baseFileName = [deleteList(k).name];
  fullFileName = fullfile(outputfolder, baseFileName);
  fprintf(1, 'Now deleting %s\n', fullFileName);
  delete(fullFileName);
end

for f = 1:length(fileList)
    SweepAmp = [];StimOff = []; StimOn = []; BinaryLP = []; BinarySP = [];
    datFile = HEKA_Importer([mainfolder, fileList(f).name]);
    sesstionStart = datetime(datFile.trees.dataTree{1, 1}.RoStartTimeMATLAB);
    posCount = 1;
    for p = 1:size(datFile.trees.ampTree,1)
      if ~isempty(datFile.trees.ampTree{p, 3})
          ampPos(posCount) = p;
          posCount = posCount+1;
      end
    end 
    if length(ampPos) > height(datFile.RecTable)   
       ampPos = ampPos(1:2:length(ampPos));
    end
    CellCounter = CellCounter + 1;
    labels = regexp(fileList(f).name, '_', 'split');
    if CellCounter < 10
      CellTag = ['0', num2str(CellCounter)];
    else
      CellTag = num2str(CellCounter);
    end 
    ID = ['Goettingen', '_Cell', CellTag];
    disp(['New cell found, ID: ', ID]) 
    %% Initializing variables for Sweep table construction
    sweepCount = 0;
    sweep_series_objects_ch1 = []; sweep_series_objects_ch2 = [];        
    %% Initializing nwb file and adding first global descriptors
    nwb = NwbFile();
    nwb.identifier = ID;
    nwb.session_description = ...
      'Characterizing intrinsic biophysical properties of cortical NHP neurons';         
    nwb.general_institution = 'University of Goettingen';
    device_name = ['HEKA Patchmaster ', ...
                         datFile.trees.ampTree{1, 1}.RoAmplifierName];        
    nwb.session_start_time = sesstionStart;   
    ic_elec_name = 'Electrode 1';  
    temp_vec = [];
    dur = duration.empty(height(datFile.RecTable.TimeStamp),0);
    for i = 1:height(datFile.RecTable.TimeStamp) 
      dur(i) = datFile.RecTable.TimeStamp{i,1}(...
         length(datFile.RecTable.TimeStamp{i,1})) - datFile.RecTable.TimeStamp{i,1}(1);   
      temp_vec(i) = datFile.RecTable.Temperature(i);
    end
    Temperature = nansum(temp_vec.*(dur/nansum(dur)));
    %% Getting run and electrode associated properties  
    nwb.general_devices.set(device_name, types.core.Device());
    device_link = types.untyped.SoftLink(['/general/devices/' device_name]);
    ic_elec = types.core.IntracellularElectrode( ...
        'device', device_link, ...
        'description', 'Properties of electrode and run associated to it',...
        'filtering', 'unknown',...
        'initial_access_resistance', ...
                  num2str(datFile.RecTable.Rs_uncomp{1,1}{1, 1}(1)/1.0e+06) ,...
        'location', 'has to be entered manually', ...
         'slice', ['Temperature ', num2str(Temperature)]...
   );

    nwb.general_intracellular_ephys.set(ic_elec_name, ic_elec);
    ic_elec_link = types.untyped.SoftLink([ ...
                         '/general/intracellular_ephys/' ic_elec_name]);   
    for e = 1:height(datFile.RecTable)       
         for s = 1:datFile.RecTable.nSweeps(e)
             if ~contains(datFile.RecTable.Stimulus(e), 'sine')
             stimData = datFile.RecTable.stimWave{e,1}.DA_3(:,s);
             
             if length(stimData) < 9900
               SweepAmp(sweepCount+1,1) = round(1000*mean(nonzeros(stimData)));                 
             else
               SweepAmp(sweepCount+1,1) = round(1000*mean(nonzeros(stimData(9900:end))));
             end
             if SweepAmp(sweepCount+1,1) <= 0
                [~, temp] = findpeaks(diff(stimData));
                StimOff(sweepCount+1,1) = temp(length(temp));
                [~, temp] = findpeaks(diff(-stimData));
                StimOn(sweepCount+1,1) = temp(length(temp));
             else
                [~, temp] = findpeaks(diff(stimData));
                StimOn(sweepCount+1,1) = temp(length(temp));
                [~, temp] = findpeaks(diff(-stimData));
                StimOff(sweepCount+1,1) = temp(length(temp));
             end
             
            stimDuration = StimOff(sweepCount+1,1)-StimOn(sweepCount+1,1);
            if  stimDuration/round(datFile.RecTable.SR(e)) == 1
             stimDescrp = 'Long Pulse';  
             BinaryLP(sweepCount+1,1)  = 1;
             BinarySP(sweepCount+1,1)  = 0;
            elseif stimDuration/round(datFile.RecTable.SR(e)) == 0.003
             stimDescrp = 'Short Pulse';
             BinaryLP(sweepCount+1,1) = 0;
             BinarySP(sweepCount+1,1)  = 1;
            else
             disp(['Unknown stimulus type with duration of '...
                        , num2str(stimDuration/round(datFile.RecTable.SR(e))), 's'])
             BinaryLP(sweepCount+1,1) = 0;
             BinarySP(sweepCount+1,1)  = 0;                    
            end
            
             
             ampState = datFile.trees.ampTree{ampPos(e), 3}.AmAmplifierState;
             t = datFile.RecTable.TimeStamp{e,1}(s);
             startT = seconds(hours(t.Hour)+ minutes(t.Minute)+seconds(t.Second));               
             
             ccs = types.core.CurrentClampStimulusSeries( ...
                    'electrode', ic_elec_link, ...
                    'gain', NaN, ...
                    'stimulus_description', datFile.RecTable.Stimulus(e), ...
                    'data_unit', cell2mat(datFile.RecTable.stimUnit{2,1}(1)), ...
                    'data', stimData, ...
                    'sweep_number', sweepCount,...
                    'starting_time', startT,...
                    'starting_time_rate', round(datFile.RecTable.SR(e))...
                    );
                                           
             nwb.stimulus_presentation.set(['Sweep_', num2str(sweepCount)], ccs);    

             nwb.acquisition.set(['Sweep_', num2str(sweepCount)], ...
                  types.core.CurrentClampSeries( ...
                    'bias_current', datFile.RecTable.Vhold{e,1}{1, 2}(s), ... % Unit: Amp
                    'bridge_balance', ampState.sRsValue , ... % Unit: Ohm
                    'capacitance_compensation', ampState.sCFastAmp2, ... % Unit: Farad
                    'data', datFile.RecTable.dataRaw{e,1}{1, 2}(:,s), ...
                    'data_unit', cell2mat(datFile.RecTable.ChUnit{2,1}(2)), ...
                    'electrode', ic_elec_link, ...
                    'stimulus_description', datFile.RecTable.Stimulus(e), ...   
                    'sweep_number', sweepCount,...
                    'starting_time', startT,...
                    'starting_time_rate', round(datFile.RecTable.SR(e))...
                      ));
                    
                sweep_ch2 = types.untyped.ObjectView(['/acquisition/', 'Sweep_', num2str(sweepCount)]);
                sweep_ch1 = types.untyped.ObjectView(['/stimulus/presentation/', 'Sweep_', num2str(sweepCount)]);
                sweep_series_objects_ch1 = [sweep_series_objects_ch1, sweep_ch1]; 
                sweep_series_objects_ch2 = [sweep_series_objects_ch2, sweep_ch2];
                sweepCount =  sweepCount + 1;   
             end
         end
    end
          %% Sweep table
      sweep_nums_vec = [[0:sweepCount-1],[0:sweepCount-1]];

      sweep_nums = types.hdmf_common.VectorData('data', sweep_nums_vec, ...
                                      'description','sweep numbers');                                     
      series_ind = types.hdmf_common.VectorIndex(...
              'data',  [0:length(sweep_nums_vec)-1],...                                      % 0-based indices to sweep_series_objects
               'target', types.untyped.ObjectView('/general/intracellular_ephys/sweep_table/series'));
      series_data = types.hdmf_common.VectorData(...
                          'data', [sweep_series_objects_ch1, sweep_series_objects_ch2],...
                          'description', 'Jagged Array of Patch Clamp Series Objects');
      sweepTable = types.core.SweepTable(...
            'colnames', {'series', 'sweep_number', 'SweepAmp', 'StimOn', 'StimOff'...
            'StimLength', 'BinaryLP', 'BinarySP'},...
            'description', 'Sweep table for single electrode aquisitions',...
            'id', types.hdmf_common.ElementIdentifiers('data',  [0:length(sweep_nums_vec)-1]),...
            'series_index', series_ind,...
            'series', series_data,...
            'sweep_number', sweep_nums);
      nwb.general_intracellular_ephys_sweep_table = sweepTable;      
      
              nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'SweepAmp') = ...
          types.hdmf_common.VectorData(...
           'description', 'amplitdue of the current step injected (if square pulse)',...
           'data',[[SweepAmp(~isnan(SweepAmp))]', [SweepAmp]']...
              ); 
          
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimOn') = ...
          types.hdmf_common.VectorData(...
           'description', 'Index of stimulus onset',...
           'data', [[StimOn(~isnan(StimOn))]', [StimOn]']...
              );   
              
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimOff') = ...
          types.hdmf_common.VectorData(...
           'description', 'Index of end of stimulus',...
           'data', [[StimOff(~isnan(StimOff))]', [StimOff]']...
              );   
    
    StimDuration = [];
    StimDuration = StimOff - StimOn;
    
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'StimLength') = ...
          types.hdmf_common.VectorData(...
           'description', 'Stimulus Length',...
           'data', [[StimDuration(~isnan(StimDuration))]', [StimDuration]']...
              );   
   nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'BinaryLP') = ...
          types.hdmf_common.VectorData(...
           'description', 'Binary tag for sweep being a long pulse protocol',...
           'data', [[BinaryLP(~isnan(BinaryLP))]', [BinaryLP]']...
              );   
          
    nwb.general_intracellular_ephys_sweep_table.vectordata.map(...
        'BinarySP') = ...
          types.hdmf_common.VectorData(...
           'description', 'Binary tag for sweep being a  pulse protocol',...
           'data',  [[BinarySP(~isnan(BinarySP))]', [BinarySP]']...
              );   
          
      filename = fullfile([outputfolder ,nwb.identifier '.nwb']);
      nwbExport(nwb, filename);
end
