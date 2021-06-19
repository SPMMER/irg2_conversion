clear

mainfolder = 'C:\Users\MFeyerabend\Dropbox\IRG2_reference_data\Pittsburgh'; %fullfile(cd, '\test_cell\');
outputfolder = 'D:\output_MATNWB\'; %[cd, '\'];
cellList = getCellNames(mainfolder);
%T = readtable('manual_entry_data.csv');
sessionTag = 'MXX';

for n = 1:length(cellList)
    cellID = cellList(n).name;
    disp(cellID)  
    fileList = dir([mainfolder,'/',cellList(n,1).name,'/*.mat']);
  
    %% Initializing variables for Sweep table construction

    sweepCount = 0;
    sweep_series_objects_ch1 = []; sweep_series_objects_ch2 = [];
    
    %% Initializing nwb file and adding first global descriptors
    nwb = NwbFile();
    nwb.identifier = cellList(n,1).name;
    nwb.session_description = ...
      'Characterizing intrinsic biophysical properties of cortical NHP neurons';
    %idx = find(strcmp(T.IDS, cellID));
%     if isempty(idx)
%         disp('Manual entry data not found')
%          nwb.general_subject = types.core.Subject( ...
%       'description', 'NA', 'age', 'NA', ...
%       'sex', 'NA', 'species', 'NA');
%     else    
%       nwb.general_subject = types.core.Subject( ...
%         'description', T.SubjectID(idx), 'age', num2str(T.SubjectAge(idx)), ...
%         'sex', T.SubjectSex(idx), 'species', T.SubjectBreed(idx));
%     end
     nwb.general_institution = 'University of Pittsburgh';
     device_name = 'CED digitizer XXXX; Amplifier: Axon MultiClamp 700B';

    %% loading the matlab converted cfs files
    paths = fullfile({fileList.folder}, {fileList.name});
    for f = 1:length(fileList)
       load(paths{f})
       
    %% Getting start date from 1st recording of cell and checking for new session start 
        if f==1 
           cellStart = datetime([D.param.fDate(1:end-3), ...
               '/20', D.param.fDate(end-1:end),' ', D.param.fTime]...
            ,'TimeZone', 'local');
        end
        nwb.session_start_time = cellStart;
    %% load JSON files if present    
        if isfile([mainfolder,cellID,'\', fileList(f).name(1:end-3), 'json'])
          raw = fileread([mainfolder,cellID,'\', fileList(f).name(1:end-3), 'json']); 
          settingsMCC = jsondecode(raw);
          cellsFieldnames = fieldnames(settingsMCC);               
          ic_elec_name = cellsFieldnames{1, 1}(2:end);
          electOffset = settingsMCC.(cellsFieldnames{1,1}).GetPipetteOffset; 
         else
          ic_elec_name = 'unknown electrode'; 
          electOffset = NaN;
         end 
   %% Getting run and electrode associated properties  
        nwb.general_devices.set(device_name, types.core.Device());
        device_link = types.untyped.SoftLink(['/general/devices/' device_name]);
        ic_elec = types.core.IntracellularElectrode( ...
            'device', device_link, ...
            'description', 'Properties of electrode and run associated to it',...
            'filtering', 'unknown',...
            'initial_access_resistance', 'has to be entered manually',...
            'location', 'has to be entered manually' ...
               );
        nwb.general_intracellular_ephys.set(ic_elec_name, ic_elec);
        ic_elec_link = types.untyped.SoftLink(['/general/intracellular_ephys/' ic_elec_name]);     
        
    %% Data: recreating the stimulus waveform
       if f==1
           stimulus_name = 'Long Pulse' ;  
       elseif f ==2
           stimulus_name = 'Short Pulse' ;  
       end           
            for s = 1:size(D.data,2)

                ccs = types.core.CurrentClampStimulusSeries( ...
                        'electrode', ic_elec_link, ...
                        'gain', NaN, ...
                        'stimulus_description', stimulus_name, ...
                        'data_unit', D.param.yUnits{2}, ...
                        'data', D.data(:,s,2), ...
                        'sweep_number', sweepCount,...
                        'starting_time', seconds(duration(D.param.fTime)),...
                        'starting_time_rate', round(1/D.param.xScale(2))...
                        );
                    
                nwb.stimulus_presentation.set(['Sweep_', num2str(sweepCount)], ccs);    

                nwb.acquisition.set(['Sweep_', num2str(sweepCount)], ...
                    types.core.CurrentClampSeries( ...
                        'bias_current', [], ... % Unit: Amp
                        'bridge_balance', [], ... % Unit: Ohm
                        'capacitance_compensation', [], ... % Unit: Farad
                        'data', D.data(:,s,1), ...
                        'data_unit', D.param.yUnits{1}, ...
                        'electrode', ic_elec_link, ...
                        'stimulus_description', stimulus_name, ...   
                        'sweep_number', sweepCount,...
                        'starting_time', seconds(duration(D.param.fTime)),...
                        'starting_time_rate', round(1/D.param.xScale(1))...
                          ));
                    
                sweep_ch2 = types.untyped.ObjectView(['/acquisition/', 'Sweep_', num2str(sweepCount)]);
                sweep_ch1 = types.untyped.ObjectView(['/stimulus/presentation/', 'Sweep_', num2str(sweepCount)]);
                sweep_series_objects_ch1 = [sweep_series_objects_ch1, sweep_ch1]; 
                sweep_series_objects_ch2 = [sweep_series_objects_ch2, sweep_ch2];
                sweepCount =  sweepCount + 1;   
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
                'colnames', {'series', 'sweep_number'},...
                'description', 'Sweep table for single electrode aquisitions',...
                'id', types.hdmf_common.ElementIdentifiers('data',  [0:length(sweep_nums_vec)-1]),...
                'series_index', series_ind,...
                'series', series_data,...
                'sweep_number', sweep_nums);
            nwb.general_intracellular_ephys_sweep_table = sweepTable;
        
    end
    filename = fullfile([outputfolder ,nwb.identifier '.nwb']);
    nwbExport(nwb, filename);
end
