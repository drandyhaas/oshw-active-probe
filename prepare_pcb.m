function [CSX, port] = prepare_pcb(CSX, excite_port)

layer_names = {'Top', 'Ground', 'Signal/Power', 'Bottom'};
resistors = {
	struct('name', 'R1',  'orientation', 'x', 'value', 100, 'height', 500e-6),
	struct('name', 'R2',  'orientation', 'x', 'value', 1.6e6, 'height', 500e-6),
	struct('name', 'R3',  'orientation', 'x', 'value', 200e3, 'height', 500e-6),
	struct('name', 'R4',  'orientation', 'x', 'value', 976e3, 'height', 500e-6),
	struct('name', 'R6',  'orientation', 'x', 'value', 66.5e3, 'height', 500e-6),
	struct('name', 'R10', 'orientation', 'x', 'value', 10e6, 'height', 500e-6),
	struct('name', 'R11', 'orientation', 'x', 'value', 68, 'height', 500e-6),
	struct('name', 'R15', 'orientation', 'x', 'value', 82, 'height', 500e-6),
	struct('name', 'R16', 'orientation', 'x', 'value', 200e3, 'height', 500e-6),
	struct('name', 'R17', 'orientation', 'x', 'value', 953e3, 'height', 500e-6)
};
capacitors = {
	struct('name', 'C1', 'orientation', 'x', 'value', 330e-12, 'height', 500e-6)
};
physical_constants;
lambda = c0/sqrt(3.68)/3e9;
fine_resolution = lambda/160;
coarse_resolution = lambda/40;
grid_duplicate_threshold = lambda/1000;
air_space = 5e-3;

% Get grid
mesh.x = CSX.RectilinearGrid.XLines;
mesh.y = CSX.RectilinearGrid.YLines;
mesh.z = CSX.RectilinearGrid.ZLines;

mesh.x(end+1) = min(mesh.x) - air_space;
mesh.x(end+1) = max(mesh.x) + air_space;
mesh.y(end+1) = min(mesh.y) - air_space;
mesh.y(end+1) = max(mesh.y) + air_space;
mesh.z(end+1) = min(mesh.z) - air_space;
mesh.z(end+1) = max(mesh.z) + air_space;

%% 1. Add via grids
type = GetPropertyType(CSX, 'via');
pos = GetPropertyPosition(CSX, type, 'via');
for n=1:numel(CSX.Properties.(type){pos}.Primitives.('Cylinder'))
	prim = CSX.Properties.(type){pos}.Primitives.('Cylinder'){n};
	mesh.x(end+1) = prim.P1.ATTRIBUTE.X;
	mesh.y(end+1) = prim.P1.ATTRIBUTE.Y;
	mesh.z(end+1) = prim.P1.ATTRIBUTE.Z;
	mesh.z(end+1) = prim.P2.ATTRIBUTE.Z;
end
mesh = CleanMesh(mesh, grid_duplicate_threshold);

%% 2. Add z levels for layer
for n=1:numel(layer_names)
	type = GetPropertyType(CSX, [layer_names{n} '_copper']);
	pos = GetPropertyPosition(CSX, type, [layer_names{n} '_copper']);
	prop_types = fieldnames(CSX.Properties.(type){pos}.Primitives);
	mesh.z(end+1) = CSX.Properties.(type){pos}.Primitives.(prop_types{1}){1}.ATTRIBUTE.Elevation;
	layer_height.(layer_names{n}) = CSX.Properties.(type){pos}.Primitives.(prop_types{1}){1}.ATTRIBUTE.Elevation;
end

%% 3. Add components
% Materials
CSX = AddMetal(CSX, 'metal');
alumina_er = 9.4;
CSX = AddMaterial(CSX, 'alumina');
CSX = SetMaterialProperty(CSX, 'alumina', 'Epsilon', alumina_er);
for n=1:numel(resistors)
	[pad1_material, pad1_start, pad1_stop] = GetHyperLynxPort(CSX, [resistors{n}.name '.1']);
	[pad2_material, pad2_start, pad2_stop] = GetHyperLynxPort(CSX, [resistors{n}.name '.2']);
	CSX = AddLumpedElement(CSX, [resistors{n}.name '-' resistors{n}.orientation '-' num2str(resistors{n}.value)], resistors{n}.orientation, 'Caps', 0, 'R', resistors{n}.value);
    if (strcmp(resistors{n}.orientation, 'x'))
        term1_start = [(pad1_start(1) + pad1_stop(1))/2, pad1_start(2), pad1_start(3)];
        term1_stop = [(pad1_start(1) + pad1_stop(1))/2, pad1_stop(2), pad1_start(3) + resistors{n}.height];
        term2_start = [(pad2_start(1) + pad2_stop(1))/2, pad2_start(2), pad1_start(3)];
        term2_stop = [(pad2_start(1) + pad2_stop(1))/2, pad2_stop(2), pad1_start(3) + resistors{n}.height];
        res_start = [(pad1_start(1) + pad1_stop(1))/2, pad1_start(2), pad1_start(3)+ resistors{n}.height];
        res_stop = term2_stop;
    else
        term1_start = [pad1_start(1), (pad1_start(2) + pad1_stop(2))/2, pad1_start(3)];
        term1_stop = [pad1_stop(1), (pad1_start(2) + pad1_stop(2))/2, pad1_start(3) + resistors{n}.height];
        term2_start = [pad2_start(1), (pad2_start(2) + pad2_stop(2))/2, pad1_start(3)];
        term2_stop = [pad2_stop(1), (pad2_start(2) + pad2_stop(2))/2, pad1_start(3) + resistors{n}.height];
        res_start = [pad1_start(1), (pad1_start(2) + pad1_stop(2))/2, pad1_start(3) + resistors{n}.height];
        res_stop = term2_stop;
    end
	CSX = AddBox(CSX, 'metal', 200, term1_start, term1_stop);
	CSX = AddBox(CSX, 'metal', 200, term2_start, term2_stop);
	CSX = AddBox(CSX, 'alumina', 150, term1_start, term2_stop);
	CSX = AddBox(CSX, [resistors{n}.name '-' resistors{n}.orientation '-' num2str(resistors{n}.value)], 300, res_start, res_stop);
	mesh = AddComponentMeshLines(mesh, term1_start, term2_stop);
end
for n=1:numel(capacitors)
	[pad1_material, pad1_start, pad1_stop] = GetHyperLynxPort(CSX, [capacitors{n}.name '.1']);
	[pad2_material, pad2_start, pad2_stop] = GetHyperLynxPort(CSX, [capacitors{n}.name '.2']);
	CSX = AddLumpedElement(CSX, [capacitors{n}.name '-' capacitors{n}.orientation '-' num2str(capacitors{n}.value)], capacitors{n}.orientation, 'Caps', 1, 'C', capacitors{n}.value);
    if (strcmp(capacitors{n}.orientation, 'x'))
        component_start = [min(pad1_stop(1), pad2_stop(1));pad1_start(2);pad1_start(3)];
        component_stop = [max(pad1_start(1), pad2_start(1));pad2_stop(2);pad1_start(3) + capacitors{n}.height];
    else
        component_start = [pad1_start(1);min(pad1_stop(2), pad2_stop(2));pad1_start(3)];
        component_stop = [pad2_stop(1);max(pad1_start(2), pad2_start(2));pad1_start(3) + capacitors{n}.height];
    end
	CSX = AddBox(CSX, [capacitors{n}.name '-' capacitors{n}.orientation '-' num2str(capacitors{n}.value)], 300, component_start, component_stop);
	mesh = AddComponentMeshLines(mesh, component_start, component_stop);
end

%% 4. Add probe tips
tip_dia = 1.4e-3;
tip_extend = 3e-3;
tip_len = 4.5e-3;

[pad1_material, pad1_start, pad1_stop] = GetHyperLynxPort(CSX, 'J1.1');
tip_port_stop = [0, pad1_start(2), layer_height.('Top')];
tip_port_start = [0, 12.852e-3, layer_height.('Top')];
pgon = [];
pgon(:, end+1) = [13.95e-3; 2.825e-3];
pgon(:, end+1) = [13.95e-3; .75e-3];
pgon(:, end+1) = [0; .75e-3];
pgon(:, end+1) = [0; 12.852e-3];
pgon(:, end+1) = [5.645e-3; 11.13e-3];
CSX = AddPolygon(CSX, 'metal', 300, 2, layer_height.('Top'), pgon);

[pad1_material, pad1_start, pad1_stop] = GetHyperLynxPort(CSX, 'J2.1');
component_start = [pad1_start(1) - tip_extend, (pad1_start(2) + pad1_stop(2) - tip_dia)/2, pad1_start(3)];
component_stop = [pad1_start(1) + tip_len, (pad1_start(2) + pad1_stop(2) + tip_dia)/2, pad1_start(3) + tip_dia];
CSX = AddBox(CSX, 'metal', 300, component_start, component_stop);

%% 5. Add ports
% Port 1 is the tip
[CSX, port{1}] = AddLumpedPort(CSX, 999, 1, 50, tip_port_start, tip_port_stop, [0 1 0], 1 == excite_port);
mesh = AddComponentMeshLines(mesh, tip_port_start, tip_port_stop);
mesh.y(end+1) = .5*(tip_port_start + tip_port_stop)(2);
mesh.z(end+1) = .5*(tip_port_start + tip_port_stop)(3);
% Port 2 is BUF802 input
[pad_material, pad_start, pad_stop] = GetHyperLynxPort(CSX, 'U1.2');
[gnd_material, gnd_start, gnd_stop] = GetHyperLynxPort(CSX, 'U1.17');
port_2_stop = [pad_stop(1) - 32e-6, pad_start(2), pad_start(3)];
port_2_start = [gnd_start(1), pad_stop(2), pad_stop(3)];
[CSX, port{2}] = AddLumpedPort(CSX, 999, 2, 50, port_2_start, port_2_stop, [1 0 0], 2 == excite_port);
mesh = AddComponentMeshLines(mesh, port_2_start, port_2_stop);
mesh.x(end+1) = .5*(port_2_start + port_2_stop)(1);
% Port 3 is BUF802 input bias
[pad_material, pad_start, pad_stop] = GetHyperLynxPort(CSX, 'U1.3');
port_3_stop = [pad_stop(1) - 32e-6, pad_start(2), pad_start(3)];
port_3_start = [gnd_start(1), pad_stop(2), pad_stop(3)];
[CSX, port{3}] = AddLumpedPort(CSX, 999, 3, 50, port_3_start, port_3_stop, [1 0 0], 3 == excite_port);
mesh = AddComponentMeshLines(mesh, port_3_start, port_3_stop);
mesh.x(end+1) = .5*(port_3_start + port_3_stop)(1);
% Port 4 is op amp + input
[pad_material, pad_start, pad_stop] = GetHyperLynxPort(CSX, 'U2.3');
port_4_stop = [(pad_start(1) + pad_stop(1))/2, pad_start(2), pad_start(3)];
port_4_start = [(pad_start(1) + pad_stop(1))/2, pad_stop(2), layer_height.('Ground')];
[CSX, port{4}] = AddLumpedPort(CSX, 999, 4, 50, port_4_start, port_4_stop, [0 0 1], 4 == excite_port);
mesh = AddComponentMeshLines(mesh, port_4_start, port_4_stop);
mesh.y(end+1) = .5*(port_4_start + port_4_stop)(2);
mesh.z(end+1) = .5*(port_4_start + port_4_stop)(3);

%% 6. Meshing
% Remove duplicates and nearly-coincident lines

% Detail box
% detail_x = [0.0065, 0.0084];
% detail_y = [0.0132, 0.0154];
% mesh.x = [mesh.x, RecursiveSmoothMesh([mesh.x(logical(detail_x(1) <= mesh.x & mesh.x <= detail_x(2)))], fine_resolution, 1.3)];
% mesh.y = [mesh.y, RecursiveSmoothMesh([mesh.y(logical(detail_y(1) <= mesh.y & mesh.y <= detail_y(2)))], fine_resolution, 1.3)];

mesh = AddThirdsMeshLines(mesh, 6.6e-3, 8.3e-3, 13.5e-3, 15.25e-3, fine_resolution);
mesh = CleanMesh(mesh, grid_duplicate_threshold);

mesh.x = RecursiveSmoothMesh(mesh.x, coarse_resolution, 1.3);
mesh.y = RecursiveSmoothMesh(mesh.y, coarse_resolution, 1.3);
mesh.z = RecursiveSmoothMesh(mesh.z, coarse_resolution, 1.3);

mesh = AddPML(mesh, 8);

CSX = DefineRectGrid(CSX, 1, mesh);

%% 7. Dump box
if (excite_port == 1)
	CSX = AddDump(CSX, 'Ef', 'DumpType', 10, 'Frequency', [1e9, 2e9]);
	CSX = AddDump(CSX, 'Hf', 'DumpType', 11, 'Frequency', [1e9, 2e9]);
	CSX = AddBox(CSX, 'Ef', 10, [-0.003, 0.007, -0.003], [0.022, 0.02, 0.003]);
	CSX = AddBox(CSX, 'Hf', 10, [-0.003, 0.007, -0.003], [0.022, 0.02, 0.003]);
end
