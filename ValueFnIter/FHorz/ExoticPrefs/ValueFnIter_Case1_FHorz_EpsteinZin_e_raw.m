function [V,Policy2]=ValueFnIter_Case1_FHorz_EpsteinZin_e_raw(n_d,n_a,n_z,n_e,N_j, d_grid, a_grid, z_grid,e_grid, pi_z,pi_e, ReturnFn, Parameters, DiscountFactorParamNames, ReturnFnParamNames, vfoptions, sj, warmglow, ezc1,ezc2,ezc3,ezc4,ezc5,ezc6,ezc7)

N_d=prod(n_d);
N_a=prod(n_a);
N_z=prod(n_z);
N_e=prod(n_e);

V=zeros(N_a,N_z,N_e,N_j,'gpuArray');
Policy=zeros(N_a,N_z,N_e,N_j,'gpuArray'); %first dim indexes the optimal choice for d and aprime rest of dimensions a,z

%%

eval('fieldexists_pi_z_J=1;vfoptions.pi_z_J;','fieldexists_pi_z_J=0;')
eval('fieldexists_ExogShockFn=1;vfoptions.ExogShockFn;','fieldexists_ExogShockFn=0;')
eval('fieldexists_ExogShockFnParamNames=1;vfoptions.ExogShockFnParamNames;','fieldexists_ExogShockFnParamNames=0;')

eval('fieldexists_EiidShockFn=1;vfoptions.EiidShockFn;','fieldexists_EiidShockFn=0;')
eval('fieldexists_EiidShockFnParamNames=1;vfoptions.EiidShockFnParamNames;','fieldexists_EiidShockFnParamNames=0;')
eval('fieldexists_pi_e_J=1;vfoptions.pi_e_J;','fieldexists_pi_e_J=0;')

if vfoptions.lowmemory>0
    special_n_e=ones(1,length(n_e));
    % e_gridvals is created below
end
if vfoptions.lowmemory>1
    l_z=length(n_z);
    special_n_z=ones(1,l_z);
    % z_gridvals is created below
end



%% j=N_j

% Create a vector containing all the return function parameters (in order)
ReturnFnParamsVec=CreateVectorFromParams(Parameters, ReturnFnParamNames,N_j);
DiscountFactorParamsVec=CreateVectorFromParams(Parameters, DiscountFactorParamNames,N_j);
DiscountFactorParamsVec=prod(DiscountFactorParamsVec);
if vfoptions.EZoneminusbeta==1
    ezc1=1-DiscountFactorParamsVec; % Just in case it depends on age
end

if fieldexists_pi_z_J==1
    z_grid=vfoptions.z_grid_J(:,N_j);
    pi_z=vfoptions.pi_z_J(:,:,N_j);
elseif fieldexists_ExogShockFn==1
    if fieldexists_ExogShockFnParamNames==1
        ExogShockFnParamsVec=CreateVectorFromParams(Parameters, vfoptions.ExogShockFnParamNames,N_j);
        ExogShockFnParamsCell=cell(length(ExogShockFnParamsVec),1);
        for ii=1:length(ExogShockFnParamsVec)
            ExogShockFnParamsCell(ii,1)={ExogShockFnParamsVec(ii)};
        end
        [z_grid,pi_z]=vfoptions.ExogShockFn(ExogShockFnParamsCell{:});
        z_grid=gpuArray(z_grid); pi_z=gpuArray(pi_z);
    else
        [z_grid,pi_z]=vfoptions.ExogShockFn(N_j);
        z_grid=gpuArray(z_grid); pi_z=gpuArray(pi_z);
    end
end
if fieldexists_pi_e_J==1
    e_grid=vfoptions.e_grid_J(:,N_j);
    pi_e=vfoptions.pi_e_J(:,N_j);
elseif fieldexists_EiidShockFn==1
    if fieldexists_EiidShockFnParamNames==1
        EiidShockFnParamsVec=CreateVectorFromParams(Parameters, vfoptions.EiidShockFnParamNames,N_j);
        EiidShockFnParamsCell=cell(length(EiidShockFnParamsVec),1);
        for ii=1:length(EiidShockFnParamsVec)
            EiidShockFnParamsCell(ii,1)={EiidShockFnParamsVec(ii)};
        end
        [e_grid,pi_e]=vfoptions.EiidShockFn(EiidShockFnParamsCell{:});
        e_grid=gpuArray(e_grid); pi_e=gpuArray(pi_e);
    else
        [e_grid,pi_e]=vfoptions.ExogShockFn(N_j);
        e_grid=gpuArray(e_grid); pi_e=gpuArray(pi_e);
    end
end

pi_e=shiftdim(pi_e,-2); % Move to third dimension

if vfoptions.lowmemory>0
    if all(size(z_grid)==[sum(n_z),1])
        z_gridvals=CreateGridvals(n_z,z_grid,1); % The 1 at end indicates want output in form of matrix.
    elseif all(size(z_grid)==[prod(n_z),l_z])
        z_gridvals=z_grid;
    end
    if all(size(e_grid)==[sum(n_e),1]) % kronecker (cross-product) grid
        e_gridvals=CreateGridvals(n_e,e_grid,1); % The 1 at end indicates want output in form of matrix.
    elseif all(size(e_grid)==[prod(n_e),length(n_e)]) % joint-grid
        e_gridvals=e_grid;
    end
end


% If there is a warm-glow at end of the final period, evaluate the warmglowfn
if warmglow==1
    WGParamsVec=CreateVectorFromParams(Parameters, vfoptions.WarmGlowBequestsFnParamsNames,N_j);
    WGmatrixraw=CreateWarmGlowFnMatrix_Case1_Disc_Par2(vfoptions.WarmGlowBequestsFn, n_a, a_grid, WGParamsVec);
    WGmatrix=WGmatrixraw;
    WGmatrix(isfinite(WGmatrixraw))=(ezc4*WGmatrixraw(isfinite(WGmatrixraw))).^ezc5;
    WGmatrix(WGmatrixraw==0)=0; % otherwise zero to negative power is set to infinity
    if ~isfield(vfoptions,'V_Jplus1')
        WGmatrix(isfinite(WGmatrixraw))=ezc3*DiscountFactorParamsVec*(((1-sj(N_j))*WGmatrix(isfinite(WGmatrixraw))).^ezc6);
        WGmatrix(WGmatrixraw==0)=0;
    end
    % Now just make it the right shape (currently has aprime, needs the d,a,z dimensions)
    if ~isfield(vfoptions,'V_Jplus1')
        if vfoptions.lowmemory==0
            WGmatrix=kron(WGmatrix,ones(N_d,1)).*ones(1,N_a,N_z,N_e);
        elseif vfoptions.lowmemory==1
            WGmatrix=kron(WGmatrix,ones(N_d,1)).*ones(1,N_a,N_z);
        elseif vfoptions.lowmemory==2
            WGmatrix=kron(WGmatrix,ones(N_d,1)).*ones(1,N_a);
        end
    else
        if vfoptions.lowmemory==0 || vfoptions.lowmemory==1
            WGmatrix=kron(WGmatrix,ones(N_d,1)).*ones(1,N_a);
        elseif vfoptions.lowmemory==2
            WGmatrix=kron(WGmatrix,ones(N_d,1));
        end
    end
else
    WGmatrix=0;
end

if ~isfield(vfoptions,'V_Jplus1')
    if vfoptions.lowmemory==0

        ReturnMatrix=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z,n_e, d_grid, a_grid, z_grid,e_grid, ReturnFnParamsVec);

        % Modify the Return Function appropriately for Epstein-Zin Preferences
        becareful=logical(isfinite(ReturnMatrix).*(ReturnMatrix~=0)); % finite but not zero
        ReturnMatrix(becareful)=(ezc1*ReturnMatrix(becareful).^ezc2).^ezc7; % Otherwise can get things like 0 to negative power equals infinity
        ReturnMatrix(ReturnMatrix==0)=-Inf;

        % Calc the max and it's index
        [Vtemp,maxindex]=max(ReturnMatrix+WGmatrix,[],1);
        V(:,:,:,N_j)=Vtemp;
        Policy(:,:,:,N_j)=maxindex;

    elseif vfoptions.lowmemory==1

        for e_c=1:N_e
            e_val=e_gridvals(e_c,:);
            ReturnMatrix_e=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z, special_n_e, d_grid, a_grid, z_grid, e_val, ReturnFnParamsVec);

            % Modify the Return Function appropriately for Epstein-Zin Preferences
            becareful=logical(isfinite(ReturnMatrix_e).*(ReturnMatrix_e~=0)); % finite and not zero
            ReturnMatrix_e(becareful)=(ezc1*ReturnMatrix_e(becareful).^ezc2).^ezc7; % Otherwise can get things like 0 to negative power equals infinity
            ReturnMatrix_e(ReturnMatrix_e==0)=-Inf;

            [Vtemp,maxindex]=max(ReturnMatrix_e+WGmatrix,[],1);
            V(:,:,e_c,N_j)=Vtemp;
            Policy(:,:,e_c,N_j)=maxindex;
        end

    elseif vfoptions.lowmemory==2

        for e_c=1:N_e
            e_val=e_gridvals(e_c,:);
            for z_c=1:N_z
                z_val=z_gridvals(z_c,:);
                ReturnMatrix_ze=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, special_n_z, special_n_e, d_grid, a_grid, z_val, e_val, ReturnFnParamsVec);
                
                % Modify the Return Function appropriately for Epstein-Zin Preferences
                becareful=logical(isfinite(ReturnMatrix_ze).*(ReturnMatrix_ze~=0)); % finite and not zero
                ReturnMatrix_ze(becareful)=(ezc1*ReturnMatrix_ze(becareful).^ezc2).^ezc7; % Otherwise can get things like 0 to negative power equals infinity
                ReturnMatrix_ze(ReturnMatrix_ze==0)=-Inf;

                %Calc the max and it's index
                [Vtemp,maxindex]=max(ReturnMatrix_ze+WGmatrix,[],1);
                V(:,z_c,e_c,N_j)=Vtemp;
                Policy(:,z_c,e_c,N_j)=maxindex;
            end
        end

    end
else
    % Using V_Jplus1
    V_Jplus1=reshape(vfoptions.V_Jplus1,[N_a,N_z,N_e]);    % First, switch V_Jplus1 into Kron form

    % Part of Epstein-Zin is before taking expectation
    temp=V_Jplus1;
    temp(isfinite(V_Jplus1))=(ezc4*V_Jplus1(isfinite(V_Jplus1))).^ezc5;
    temp(V_Jplus1==0)=0; % otherwise zero to negative power is set to infinity

    % Expectation over e
    temp=sum(temp.*pi_e,3);
    
    if vfoptions.lowmemory==0
        
        %if vfoptions.returnmatrix==2 % GPU
        ReturnMatrix=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z,n_e, d_grid, a_grid, z_grid, e_grid, ReturnFnParamsVec);

        % Modify the Return Function appropriately for Epstein-Zin Preferences
        becareful=logical(isfinite(ReturnMatrix).*(ReturnMatrix~=0)); % finite and not zero
        temp2=ReturnMatrix;
        temp2(becareful)=ReturnMatrix(becareful).^ezc2;
        temp2(ReturnMatrix==0)=-Inf;

        % Calc the expectation term (except beta)
        EV=temp.*shiftdim(pi_z',-1);
        EV(isnan(EV))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
        EV=sum(EV,2); % sum over z', leaving a singular second dimension

        entireEV=repelem(EV,N_d,1,1);
        temp4=entireEV;
        if warmglow==1
            becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
            temp4(becareful)=(sj(N_j)*temp4(becareful)+(1-sj(N_j))*WGmatrix(becareful)).^ezc6;
            temp4((entireEV==0)&(WGmatrix==0))=0; % Is actually zero
        else % not using warmglow
            temp4(isfinite(temp4))=(sj(N_j)*temp4(isfinite(temp4))).^ezc6;
            temp4(entireEV==0)=0;
        end
        
        entireRHS=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a,1,N_e);

        temp5=logical(isfinite(entireRHS).*(entireRHS~=0));
        entireRHS(temp5)=ezc1*entireRHS(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
        entireRHS(entireRHS==0)=-Inf;
        
        %Calc the max and it's index
        [Vtemp,maxindex]=max(entireRHS,[],1);
        V(:,:,:,N_j)=Vtemp;
        Policy(:,:,:,N_j)=maxindex;
        
    elseif vfoptions.lowmemory==1

        % Calc the expectation term (except beta)
        EV=temp.*shiftdim(pi_z',-1);
        EV(isnan(EV))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
        EV=sum(EV,2); % sum over z', leaving a singular second dimension

        entireEV=repelem(EV,N_d,1,1);
        temp4=entireEV;
        if warmglow==1
            becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
            temp4(becareful)=(sj(N_j)*temp4(becareful)+(1-sj(N_j))*WGmatrix(becareful)).^ezc6;
            temp4((entireEV==0)&(WGmatrix==0))=0; % Is actually zero
        else % not using warmglow
            temp4(isfinite(temp4))=(sj(N_j)*temp4(isfinite(temp4))).^ezc6;
            temp4(entireEV==0)=0;
        end

        for e_c=1:N_e
            e_val=e_gridvals(e_c,:);
            ReturnMatrix_e=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z, special_n_e, d_grid, a_grid, z_grid, e_val, ReturnFnParamsVec);

            % Modify the Return Function appropriately for Epstein-Zin Preferences
            becareful=logical(isfinite(ReturnMatrix_e).*(ReturnMatrix_e~=0)); % finite and not zero
            temp2=ReturnMatrix_e;
            temp2(becareful)=ReturnMatrix_e(becareful).^ezc2;
            temp2(ReturnMatrix_e==0)=-Inf;

            entireRHS_e=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a,1);

            temp5=logical(isfinite(entireRHS_e).*(entireRHS_e~=0));
            entireRHS_e(temp5)=ezc1*entireRHS_e(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
            entireRHS_e(entireRHS_e==0)=-Inf;
            
            %Calc the max and it's index
            [Vtemp,maxindex]=max(entireRHS_e,[],1);
            V(:,:,e_c,N_j)=Vtemp;
            Policy(:,:,e_c,N_j)=maxindex;
        end
        
    elseif vfoptions.lowmemory==2
        for z_c=1:N_z
            z_val=z_gridvals(z_c,:);

            % Calc the expectation term (except beta)
            EV_z=temp.*(ones(N_a,1,'gpuArray')*pi_z(z_c,:));
            EV_z(isnan(EV_z))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
            EV_z=sum(EV_z,2); % sum over z', leaving a singular second dimension

            entireEV_z=repelem(EV_z,N_d,1,1);
            temp4=entireEV_z;
            if warmglow==1
                becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
                temp4(becareful)=(sj(N_j)*temp4(becareful)+(1-sj(N_j))*WGmatrix(becareful)).^ezc6;
                temp4((entireEV_z==0)&(WGmatrix==0))=0; % Is actually zero
            else % not using warmglow
                temp4(isfinite(temp4))=(sj(N_j)*temp4(isfinite(temp4))).^ezc6;
                temp4(entireEV_z==0)=0;
            end
                        
            for e_c=1:N_e
                e_val=e_gridvals(e_c,:);

                ReturnMatrix_ze=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, special_n_z, special_n_e, d_grid, a_grid, z_val ,e_val, ReturnFnParamsVec);
                
                % Modify the Return Function appropriately for Epstein-Zin Preferences
                becareful=logical(isfinite(ReturnMatrix_ze).*(ReturnMatrix_ze~=0)); % finite and not zero
                temp2=ReturnMatrix_ze;
                temp2(becareful)=ReturnMatrix_ze(becareful).^ezc2;
                temp2(ReturnMatrix_ze==0)=-Inf;

                entireRHS_ze=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a);

                temp5=logical(isfinite(entireRHS_ze).*(entireRHS_ze~=0));
                entireRHS_ze(temp5)=ezc1*entireRHS_ze(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
                entireRHS_ze(entireRHS_ze==0)=-Inf;

                %Calc the max and it's index
                [Vtemp,maxindex]=max(entireRHS_ze);
                V(:,z_c,e_c,N_j)=Vtemp;
                Policy(:,z_c,e_c,N_j)=maxindex;
            end
        end
        
    end
end

%% Iterate backwards through j.
for reverse_j=1:N_j-1
    jj=N_j-reverse_j;

    if vfoptions.verbose==1
        fprintf('Finite horizon: %i of %i \n',jj, N_j)
    end
    
    
    % Create a vector containing all the return function parameters (in order)
    ReturnFnParamsVec=CreateVectorFromParams(Parameters, ReturnFnParamNames,jj);
    DiscountFactorParamsVec=CreateVectorFromParams(Parameters, DiscountFactorParamNames,jj);
    DiscountFactorParamsVec=prod(DiscountFactorParamsVec);
    if vfoptions.EZoneminusbeta==1
        ezc1=1-DiscountFactorParamsVec; % Just in case it depends on age
    end

    if fieldexists_pi_z_J==1
        z_grid=vfoptions.z_grid_J(:,jj);
        pi_z=vfoptions.pi_z_J(:,:,jj);
    elseif fieldexists_ExogShockFn==1
        if fieldexists_ExogShockFnParamNames==1
            ExogShockFnParamsVec=CreateVectorFromParams(Parameters, vfoptions.ExogShockFnParamNames,jj);
            ExogShockFnParamsCell=cell(length(ExogShockFnParamsVec),1);
            for ii=1:length(ExogShockFnParamsVec)
                ExogShockFnParamsCell(ii,1)={ExogShockFnParamsVec(ii)};
            end
            [z_grid,pi_z]=vfoptions.ExogShockFn(ExogShockFnParamsCell{:});
            z_grid=gpuArray(z_grid); pi_z=gpuArray(pi_z);
        else
            [z_grid,pi_z]=vfoptions.ExogShockFn(jj);
            z_grid=gpuArray(z_grid); pi_z=gpuArray(pi_z);
        end
    end
    if fieldexists_pi_e_J==1
        e_grid=vfoptions.e_grid_J(:,jj);
        pi_e=vfoptions.pi_e_J(:,jj);
        pi_e=shiftdim(pi_e,-2); % Move to thrid dimension
    elseif fieldexists_EiidShockFn==1
        if fieldexists_EiidShockFnParamNames==1
            EiidShockFnParamsVec=CreateVectorFromParams(Parameters, vfoptions.EiidShockFnParamNames,jj);
            EiidShockFnParamsCell=cell(length(EiidShockFnParamsVec),1);
            for ii=1:length(EiidShockFnParamsVec)
                EiidShockFnParamsCell(ii,1)={EiidShockFnParamsVec(ii)};
            end
            [e_grid,pi_e]=vfoptions.EiidShockFn(EiidShockFnParamsCell{:});
            e_grid=gpuArray(e_grid); pi_e=gpuArray(pi_e);
        else
            [e_grid,pi_e]=vfoptions.EiidShockFn(jj);
            e_grid=gpuArray(e_grid); pi_e=gpuArray(pi_e);
        end
        pi_e=shiftdim(pi_e,-2); % Move to third dimension
    end
    
    if vfoptions.lowmemory>0
        if (vfoptions.paroverz==1 || vfoptions.lowmemory==2) && (fieldexists_pi_z_J==1 || fieldexists_ExogShockFn==1)
            if all(size(z_grid)==[sum(n_z),1])
                z_gridvals=CreateGridvals(n_z,z_grid,1); % The 1 at end indicates want output in form of matrix.
            elseif all(size(z_grid)==[prod(n_z),l_z])
                z_gridvals=z_grid;
            end
        end
        if (fieldexists_pi_e_J==1 || fieldexists_EiidShockFn==1)
            if all(size(e_grid)==[sum(n_e),1]) % kronecker (cross-product) grid
                e_gridvals=CreateGridvals(n_e,e_grid,1); % The 1 at end indicates want output in form of matrix.
            elseif all(size(e_grid)==[prod(n_e),length(n_e)]) % joint-grid
                e_gridvals=e_grid;
            end
        end
    end

    % If there is a warm-glow, evaluate the warmglowfn
    if warmglow==1
        WGParamsVec=CreateVectorFromParams(Parameters, vfoptions.WarmGlowBequestsFnParamsNames,jj);
        WGmatrixraw=CreateWarmGlowFnMatrix_Case1_Disc_Par2(vfoptions.WarmGlowBequestsFn, n_a, a_grid, WGParamsVec);
        WGmatrix=WGmatrixraw;
        WGmatrix(isfinite(WGmatrixraw))=(ezc4*WGmatrixraw(isfinite(WGmatrixraw))).^ezc5;
        WGmatrix(WGmatrixraw==0)=0; % otherwise zero to negative power is set to infinity
        % Now just make it the right shape (currently has aprime, needs the d,a,z dimensions)
        if vfoptions.lowmemory==0
            WGmatrix=kron(WGmatrix,ones(N_d,1)).*ones(1,1,N_z);
        elseif vfoptions.lowmemory==1 || vfoptions.lowmemory==2
            WGmatrix=kron(WGmatrix,ones(N_d,1));
        end
    end
    
    VKronNext_j=V(:,:,:,jj+1);
    % Part of Epstein-Zin is before taking expectation
    temp=VKronNext_j;
    temp(isfinite(VKronNext_j))=(ezc4*VKronNext_j(isfinite(VKronNext_j))).^ezc5;
    temp(VKronNext_j==0)=0; % otherwise zero to negative power is set to infinity

    % Expectation over e
    temp=sum(temp.*pi_e,3);
    
    if vfoptions.lowmemory==0
        
        %if vfoptions.returnmatrix==2 % GPU
        ReturnMatrix=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z,n_e, d_grid, a_grid, z_grid, e_grid, ReturnFnParamsVec);

        % Modify the Return Function appropriately for Epstein-Zin Preferences
        becareful=logical(isfinite(ReturnMatrix).*(ReturnMatrix~=0)); % finite and not zero
        temp2=ReturnMatrix;
        temp2(becareful)=ReturnMatrix(becareful).^ezc2;
        temp2(ReturnMatrix==0)=-Inf;

        % Calc the expectation term (except beta)
        EV=temp.*shiftdim(pi_z',-1);
        EV(isnan(EV))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
        EV=sum(EV,2); % sum over z', leaving a singular second dimension

        entireEV=repelem(EV,N_d,1,1);
        temp4=entireEV;
        if warmglow==1
            becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
            temp4(becareful)=(sj(jj)*temp4(becareful)+(1-sj(jj))*WGmatrix(becareful)).^ezc6;
            temp4((entireEV==0)&(WGmatrix==0))=0; % Is actually zero
        else % not using warmglow
            temp4(isfinite(temp4))=(sj(jj)*temp4(isfinite(temp4))).^ezc6;
            temp4(entireEV==0)=0;
        end
        
        entireRHS=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a,1,N_e);

        temp5=logical(isfinite(entireRHS).*(entireRHS~=0));
        entireRHS(temp5)=ezc1*entireRHS(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
        entireRHS(entireRHS==0)=-Inf;
        
        %Calc the max and it's index
        [Vtemp,maxindex]=max(entireRHS,[],1);
        V(:,:,:,jj)=Vtemp;
        Policy(:,:,:,jj)=maxindex;
        
    elseif vfoptions.lowmemory==1
        % Calc the expectation term (except beta)
        EV=temp.*shiftdim(pi_z',-1);
        EV(isnan(EV))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
        EV=sum(EV,2); % sum over z', leaving a singular second dimension

        entireEV=repelem(EV,N_d,1,1);
        temp4=entireEV;
        if warmglow==1
            becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
            temp4(becareful)=(sj(jj)*temp4(becareful)+(1-sj(jj))*WGmatrix(becareful)).^ezc6;
            temp4((entireEV==0)&(WGmatrix==0))=0; % Is actually zero
        else % not using warmglow
            temp4(isfinite(temp4))=(sj(jj)*temp4(isfinite(temp4))).^ezc6;
            temp4(entireEV==0)=0;
        end

        for e_c=1:N_e
            e_val=e_gridvals(e_c,:);
            ReturnMatrix_e=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, n_z, special_n_e, d_grid, a_grid, z_grid, e_val, ReturnFnParamsVec);

            % Modify the Return Function appropriately for Epstein-Zin Preferences
            becareful=logical(isfinite(ReturnMatrix_e).*(ReturnMatrix_e~=0)); % finite and not zero
            temp2=ReturnMatrix_e;
            temp2(becareful)=ReturnMatrix_e(becareful).^ezc2;
            temp2(ReturnMatrix_e==0)=-Inf;

            entireRHS_e=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a,1);

            temp5=logical(isfinite(entireRHS_e).*(entireRHS_e~=0));
            entireRHS_e(temp5)=ezc1*entireRHS_e(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
            entireRHS_e(entireRHS_e==0)=-Inf;
            
            %Calc the max and it's index
            [Vtemp,maxindex]=max(entireRHS_e,[],1);
            V(:,:,e_c,jj)=Vtemp;
            Policy(:,:,e_c,jj)=maxindex;
        end
        
    elseif vfoptions.lowmemory==2
        for z_c=1:N_z
            z_val=z_gridvals(z_c,:);

            % Calc the expectation term (except beta)
            EV_z=temp.*(ones(N_a,1,'gpuArray')*pi_z(z_c,:));
            EV_z(isnan(EV_z))=0; %multilications of -Inf with 0 gives NaN, this replaces them with zeros (as the zeros come from the transition probabilites)
            EV_z=sum(EV_z,2); % sum over z', leaving a singular second dimension

            entireEV_z=repelem(EV_z,N_d,1,1);
            temp4=entireEV_z;
            if warmglow==1
                becareful=logical(isfinite(temp4).*isfinite(WGmatrix)); % both are finite
                temp4(becareful)=(sj(jj)*temp4(becareful)+(1-sj(jj))*WGmatrix(becareful)).^ezc6;
                temp4((entireEV_z==0)&(WGmatrix==0))=0; % Is actually zero
            else % not using warmglow
                temp4(isfinite(temp4))=(sj(jj)*temp4(isfinite(temp4))).^ezc6;
                temp4(entireEV_z==0)=0;
            end
            
            for e_c=1:N_e
                e_val=e_gridvals(e_c,:);

                ReturnMatrix_ze=CreateReturnFnMatrix_Case1_Disc_Par2e(ReturnFn, n_d, n_a, special_n_z, special_n_e, d_grid, a_grid, z_val ,e_val, ReturnFnParamsVec);
                
                % Modify the Return Function appropriately for Epstein-Zin Preferences
                becareful=logical(isfinite(ReturnMatrix_ze).*(ReturnMatrix_ze~=0)); % finite and not zero
                temp2=ReturnMatrix_ze;
                temp2(becareful)=ReturnMatrix_ze(becareful).^ezc2;
                temp2(ReturnMatrix_ze==0)=-Inf;

                entireRHS_ze=ezc1*temp2+ezc3*DiscountFactorParamsVec*temp4*ones(1,N_a);

                temp5=logical(isfinite(entireRHS_ze).*(entireRHS_ze~=0));
                entireRHS_ze(temp5)=ezc1*entireRHS_ze(temp5).^ezc7;  % matlab otherwise puts 0 to negative power to infinity
                entireRHS_ze(entireRHS_ze==0)=-Inf;

                %Calc the max and it's index
                [Vtemp,maxindex]=max(entireRHS_ze);
                V(:,z_c,e_c,jj)=Vtemp;
                Policy(:,z_c,e_c,jj)=maxindex;
            end
        end
        
    end
end

%%
Policy2=zeros(2,N_a,N_z,N_e,N_j,'gpuArray'); %NOTE: this is not actually in Kron form
Policy2(1,:,:,:,:)=shiftdim(rem(Policy-1,N_d)+1,-1);
Policy2(2,:,:,:,:)=shiftdim(ceil(Policy/N_d),-1);

end