const USE_LIGHT_MAPS = true;
var MAP = null;
var MAP_SECTOR_FOR_X = {};
var MAP_SIZE_X = 1;
var MAP_SIZE_Y = 1;
var MAP_SIZE_Z = 1;
var GROUPS = [];
var scene = new THREE.Scene();

function load_level() {
	let sectors = JSON.parse(document.getElementById('level_sectors').innerHTML.trim());
	let sector_for_x = {};
	let i = 0;
	let s = 0;
	for (let x of sectors) {
		let group = new THREE.Group();
		GROUPS.push(group);
		scene.add(group);
		while (i <= x) {
			sector_for_x[i] = s;
			i += 1;
		}
		s += 1;
	}

	MAP_SECTOR_FOR_X = sector_for_x;

	let level = document.getElementById('level').innerHTML;
	let map = [];
	let floor = [];
	let cam_from = new THREE.Vector3();
	let cam_at = new THREE.Vector3();
	let y = 0;
	let z = 0;
	for (let line of level.split("\n")) {
		let row = [];
		line = line.replace(/\s/g, '');
		if (line.length === 0 && floor.length > 0) {
			map.push(floor);
			floor = [];
			y += 1;
			z = 0;
		} else {
			let x = 0;
			for (let c of line) {
				if (c === 'A') {
					cam_from = new THREE.Vector3(x, y, z)
					row.push(0);
				} else if (c === 'B') {
					cam_at = new THREE.Vector3(x, y, z)
					row.push(0);
				} else if (c === 'L') {
					row.push(99);
				} else if (c.charCodeAt(0) < 110) {
					row.push(0);
				} else {
					row.push(1);
				}
				x += 1;
			}
			z += 1;
			if (row.length > 0) {
				floor.push(row);
			}
		}
	}
	MAP = map;
	MAP_SIZE_Y = MAP.length;
	MAP_SIZE_Z = MAP[0].length;
	MAP_SIZE_X = MAP[0][0].length;
	let cam_dir = cam_at.sub(cam_from);
	cam_from.y = MAP_SIZE_Y - 1 - cam_from.y;
	cam.yaw = Math.atan2(-cam_dir.x, -cam_dir.z);
	cam.from = cam_from.add(new THREE.Vector3(0.5, 0.5, 0.5));
}

var MAP_MAX_SUBDIV = 4;
var MAP_MAX_SUBDIV_SIZE = 1 << MAP_MAX_SUBDIV;
var WALL_DIST = 0.15;

class Camera {
	constructor(_from, _yaw) {
		this.from = _from;
		this.velocity = new THREE.Vector3(0, 0, 0);
		this.yaw = _yaw;
		this.vyaw = 0.0;
		this.pitch = 0.0;
		this.vpitch = 0.0;
		this.roll = 0.0;
		this.vroll = 0.0;
		this.elapsed = 0;
	}
	pan(d) { this.vyaw = 0.01 * d; }
	tilt(d) { this.vpitch = 0.005 * d; }
	dolly(d) {
		this.velocity = new THREE.Vector3(0, 0, d * 0.02);
		this.velocity.applyAxisAngle(new THREE.Vector3(1, 0, 0), this.pitch);
		this.velocity.applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
	}
	boom(d) {
		this.velocity = new THREE.Vector3(0, d * 0.02, 0);
		this.velocity.applyAxisAngle(new THREE.Vector3(1, 0, 0), this.pitch);
		this.velocity.applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
	}
	truck(d) {
		this.velocity = new THREE.Vector3(d * 0.02, 0, 0);
		this.velocity.applyAxisAngle(new THREE.Vector3(1, 0, 0), this.pitch);
		this.velocity.applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
	}
	animate_step() {
		this.elapsed += 1;
		let ix = Math.floor(this.from.x);
		let iy = Math.floor(this.from.y);
		let iz = Math.floor(this.from.z);
		this.from.add(this.velocity);
		// this.velocity.y -= 0.01;
		if (this.from.x < WALL_DIST)
			this.from.x = WALL_DIST;
		if (this.from.x > MAP_SIZE_X - WALL_DIST)
			this.from.x = MAP_SIZE_X - WALL_DIST;
		if (this.from.y < WALL_DIST)
			this.from.y = WALL_DIST;
		if (this.from.y > MAP_SIZE_Y - WALL_DIST)
			this.from.y = MAP_SIZE_Y - WALL_DIST;
		if (this.from.z < WALL_DIST)
			this.from.z = WALL_DIST;
		if (this.from.z > MAP_SIZE_Z - WALL_DIST)
			this.from.z = MAP_SIZE_Z - WALL_DIST;
		if (map(ix+1, iy, iz) > 0 && this.from.x > ix+1 - WALL_DIST)
			this.from.x = ix+1 - WALL_DIST;
		if (map(ix-1, iy, iz) > 0 && this.from.x < ix + WALL_DIST)
			this.from.x = ix + WALL_DIST;
		if (map(ix, iy+1, iz) > 0 && this.from.y > iy+1 - WALL_DIST)
			this.from.y = iy+1 - WALL_DIST;
		if (map(ix, iy-1, iz) > 0 && this.from.y < iy + WALL_DIST)
			this.from.y = iy + WALL_DIST;
		if (map(ix, iy, iz+1) > 0 && this.from.z > iz+1 - WALL_DIST)
			this.from.z = iz+1 - WALL_DIST;
		if (map(ix, iy, iz-1) > 0 && this.from.z < iz + WALL_DIST)
			this.from.z = iz + WALL_DIST;
		this.velocity.multiplyScalar(0.98);

		this.pitch += this.vpitch;
		this.vpitch *= 0.98;
		this.yaw += this.vyaw;
		this.vyaw *= 0.98;
		this.vroll = this.vyaw * 0.8;
		this.roll += this.vroll;
		this.vroll *= 0.98;
		this.roll *= 0.98;

	}
	animate_to(t) {
		while (this.elapsed < t) {
			this.animate_step();
		}
	}
}

var clock = new THREE.Clock(true);

const LIGHT_ΜAP_SIZE = 512;
const ANISOTROPY = 8;
const WALL_LIGHTMAP_BUMP = 0.2;

const KEYS = {
	'ArrowUp': 'up',
	'ArrowDown': 'down',
	'ArrowLeft': 'left',
	'ArrowRight': 'right',
	// 'Space': 'jump',
	// 'a': 'forward',
	// 'z': 'backwards',
	// 's': 'strafe_up',
	// 'x': 'strafe_down',
	// 'q': 'strafe_left',
	// 'w': 'strafe_right',
	'KeyL': 'lightmap',
	// 'm': 'wireframe',
	// 'KeyW': 'forward',
	// 'KeyS': 'backwards',
	'KeyA': 'forward',
	'KeyZ': 'backwards',
	// 'ArrowUp': 'forward',
	// 'ArrowDown': 'backwards',
	// 'ArrowLeft': 'left',
	// 'ArrowRight': 'right',
};
let keys = {};

var light_scene = new THREE.Scene();

var cam = new Camera(new THREE.Vector3(1.5, 1.5, 1.5), 0.0);
load_level();

var camera = new THREE.PerspectiveCamera(60,
window.innerWidth / window.innerHeight, 0.0001, 100000);
camera.position.x = 1.5;
camera.position.z = 1.5;
camera.position.y = 0.5;
var renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setClearColor("#000");
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 2;

renderer.outputEncoding = THREE.sRGBEncoding;
document.body.appendChild(renderer.domElement);

var lm_renderer = new THREE.WebGLRenderer({ antialias: false });
lm_renderer.setClearColor("#000");
lm_renderer.setSize(LIGHT_ΜAP_SIZE, LIGHT_ΜAP_SIZE);
// document.body.appendChild(lm_renderer.domElement);
// lm_renderer.domElement.classList.add('overlay');

let renderTarget = new THREE.WebGLRenderTarget(LIGHT_ΜAP_SIZE, LIGHT_ΜAP_SIZE, {type: THREE.UnsignedByteType});

let texture_loader = new THREE.TextureLoader();

// let marble = texture_loader.load('https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/red_brick_plaster_patch_02/red_brick_plaster_patch_02_diff_1k.jpg');
// let marble = texture_loader.load('https://www.the3rdsequence.com/texturedb/download/32/texture/jpg/2048/smooth+white+tile-2048x2048.jpg');
// let marble = texture_loader.load('https://www.the3rdsequence.com/texturedb/download/116/texture/jpg/2048/irregular+wood+planks-2048x2048.jpg');
// let marble = texture_loader.load('/cypher/maze/brickwall.jpg');
let marble = texture_loader.load('/cypher/maze/smooth+white+tile-2048x2048.jpg');
marble.wrapS = THREE.RepeatWrapping;
marble.wrapT = THREE.RepeatWrapping;
marble.anisotropy = ANISOTROPY;

let light_material = new THREE.ShaderMaterial({
	vertexShader: document.getElementById('vertex-shader').textContent,
	fragmentShader: document.getElementById('fragment-shader-light').textContent
});

// let light;
// light = new THREE.Mesh(new THREE.SphereGeometry(1), light_material);
// light.scale.x = 0.4;
// light.scale.y = 0.4;
// light.scale.z = 0.4;
// light.position.x = LIGHT_X;
// light.position.y = LIGHT_Y;
// light.position.z = LIGHT_Z;
// light_scene.add(light);
// light = new THREE.Mesh(new THREE.SphereGeometry(1), light_material);
// light.scale.x = 0.4;
// light.scale.y = 0.4;
// light.scale.z = 0.4;
// light.position.x = 2;
// light.position.y = LIGHT_Y-3;
// light.position.z = 12;
// light_scene.add(light);

function map(x, y, z) {
	if (x < 0 || x >= MAP_SIZE_X || y < 0 || y >= MAP_SIZE_Y || z < 0 || z >= MAP_SIZE_Z)
		return 0;
	return MAP[MAP_SIZE_Y - 1 - y][z][x];
}

let face_geometry = new THREE.PlaneGeometry(1, 1, 1, 1);

var FACE_TWEAKS = [
	{bx: -1, by:  0, bz:  0, px: 0.0, py: 0.5, pz: 0.5, rx: 0.0, ry: -Math.PI / 2, rz: 0},
	{bx: +1, by:  0, bz:  0, px: 1.0, py: 0.5, pz: 0.5, rx: 0.0, ry: Math.PI / 2, rz: 0},
	{bx:  0, by: -1, bz:  0, px: 0.5, py: 0.0, pz: 0.5, rx: Math.PI / 2, ry: 0, rz: 0},
	{bx:  0, by: +1, bz:  0, px: 0.5, py: 1.0, pz: 0.5, rx: -Math.PI / 2, ry: 0, rz: 0},
	{bx:  0, by:  0, bz: -1, px: 0.5, py: 0.5, pz: 0.0, rx: 0, ry: Math.PI, rz: 0},
	{bx:  0, by:  0, bz: +1, px: 0.5, py: 0.5, pz: 1.0, rx: 0, ry: 0.0, rz: 0},
];
let faces = [];
let face_count = 0;
const vertices = new Float32Array([
	-0.5, -0.5, 0,
	 0.5, -0.5, 0,
	 0.5,  0.5, 0,
	-0.5,  0.5, 0
]);
const v2 = [[0, 0], [1, 0], [1, 1], [0, 1]];
const uv = [0, 0, 1, 0, 1, 1, 0, 1];
const normals = [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1];
const lightness = new Float32Array([1.0, 1.0, 1.0, 1.0]);
const indices = [];
indices.push(0, 1, 2);
indices.push(0, 2, 3);

var light_hash = {};

var face_material = new THREE.ShaderMaterial({
	uniforms: {
		texscale: { value: 1 },
		texture1: { value: marble },
	},
	vertexShader: document.getElementById('vertex-shader').textContent,
	fragmentShader: document.getElementById('fragment-shader-lightmap').textContent,
	wireframe: false,
});

for (let z = 0; z < MAP_SIZE_Z; z++) {
	for (let y = 0; y < MAP_SIZE_Y; y++) {
		for (let x = 0; x < MAP_SIZE_X; x++) {
			for (let i = 0; i < 6; i++) {
				if ((i == 0 && x == 0) || (i == 1 && x == MAP_SIZE_X-1) ||
					(i == 2 && y == 0) || (i == 3 && y == MAP_SIZE_Y-1) ||
					(i == 4 && z == 0) || (i == 5 && z == MAP_SIZE_Z-1))
					continue;
				let t = FACE_TWEAKS[i];
				if (map(x, y, z) > 0 && map(x + t.bx, y + t.by, z + t.bz) == 0) {
					let geometry = new THREE.BufferGeometry();
					geometry.setIndex(indices);
					geometry.setAttribute('position', new THREE.Float32BufferAttribute( vertices, 3 ) );
					geometry.setAttribute('uv', new THREE.Float32BufferAttribute( uv, 2 ) );
					geometry.setAttribute('lightness', new THREE.BufferAttribute(lightness, 1));

					let light_face_material = new THREE.ShaderMaterial({
						vertexShader: document.getElementById('vertex-shader').textContent,
						fragmentShader: document.getElementById('fragment-shader-lightmap-no-tex').textContent,
					});

					let face = new THREE.Mesh(geometry, face_material);
					face.position.set(x + t.px, y + t.py, z + t.pz);
					face.rotation.set(t.rx, t.ry, t.rz);
					face.updateMatrix();
					let light_hashes = [];
					for (let k = 0; k < 4; k++) {
						let matrix = face.matrix;
						let v = new THREE.Vector3(
							vertices[k * 3 + 0],
							vertices[k * 3 + 1],
							vertices[k * 3 + 2]
						);
						v.multiplyScalar(0.7);
						v.applyMatrix4(matrix);
						let pr = v.clone().round();
						let prx = Math.round(pr.x);
						let pry = Math.round(pr.y);
						let prz = Math.round(pr.z);
						let p = v.clone();
						v.multiplyScalar(MAP_MAX_SUBDIV_SIZE);
						v.round();
						let key = 0;
						key *= 6;
						key += i;
						key *= MAP_SIZE_X * MAP_MAX_SUBDIV_SIZE;
						key += v.x;
						key *= MAP_SIZE_Y * MAP_MAX_SUBDIV_SIZE;
						key += v.y;
						key *= MAP_SIZE_Z * MAP_MAX_SUBDIV_SIZE;
						key += v.z;

						let n = new THREE.Vector3(-1, 0, 0);
						if (i === 1)
							n = new THREE.Vector3(1, 0, 0);
						if (i === 2)
							n = new THREE.Vector3(0, -1, 0);
						if (i === 3)
							n = new THREE.Vector3(0, 1, 0);
						if (i === 4)
							n = new THREE.Vector3(0, 0, -1);
						if (i === 5)
							n = new THREE.Vector3(0, 0, 1);

						if (!(key in light_hash)) {
							light_hash[key] = {
								p: p,
								dir: i,
								n: n,
								lightness: USE_LIGHT_MAPS ? 0 : 1,
								faces: [],
							};
						}
						light_hash[key].faces.push(faces.length);
						light_hashes.push(key);
					}

					GROUPS[MAP_SECTOR_FOR_X[x]].add(face);
					// scene.add(face);
					let light_face = face.clone();
					light_face.material = map(x, y, z) == 99 ? light_material : light_face.material;
					light_scene.add(light_face);
					face_count += 1;
					faces.push({face: face, light_hashes: light_hashes});
				}
			}
		}
	}
}

let new_light_hash = {};
let hash_tr = {};
for (let hash in light_hash) {
	let data = light_hash[hash];
	let key = 0;
	key *= 6;
	key += data.dir;
	key *= MAP_SIZE_X * MAP_MAX_SUBDIV_SIZE;
	key += Math.round(data.p.x) * MAP_MAX_SUBDIV_SIZE;
	key *= MAP_SIZE_Y * MAP_MAX_SUBDIV_SIZE;
	key += Math.round(data.p.y) * MAP_MAX_SUBDIV_SIZE;
	key *= MAP_SIZE_Z * MAP_MAX_SUBDIV_SIZE;
	key += Math.round(data.p.z) * MAP_MAX_SUBDIV_SIZE;
	hash_tr[hash] = key;
	if (!(key in new_light_hash)) {
		new_light_hash[key] = data;
		new_light_hash[key].psum = new THREE.Vector3(0, 0, 0);
		new_light_hash[key].pcount = 0;
	}
	new_light_hash[key].psum.add(data.p);
	new_light_hash[key].pcount += 1;
}
let labels = [];
for (let hash in new_light_hash) {
	new_light_hash[hash].p = new_light_hash[hash].psum.multiplyScalar(1.0 / new_light_hash[hash].pcount);
}

light_hash = new_light_hash;

let all_light_hashes = Object.keys(light_hash).sort();

// for (let i = 0; i < all_light_hashes.length; i++) {
// 	let hash = all_light_hashes[i];
// 	let p = light_hash[hash].p
// 	let p2 = light_hash[hash].p.clone().project(camera);
// 	let x = (p2.x / p2.z) * window.innerWidth / 2 + window.innerWidth / 2;
// 	let y = (p2.y / p2.z) * window.innerHeight / 2 + window.innerHeight / 2;
// 	let el = document.createElement('div');
// 	el.classList.add('label');
// 	el.innerHTML = `${i}`;
// 	el.dataset.hash = hash;
// 	labels.push(el);
// 	document.querySelector('body').appendChild(el);
// }

for (let i = 0; i < faces.length; i++) {
	faces[i].light_hashes = faces[i].light_hashes.map(function(x) {
		return hash_tr[x];
	});
}


// if (!USE_LIGHT_MAPS) {
// 	for (let hash of all_light_hashes) {
// 		let g = new THREE.SphereGeometry(0.02);
// 		let pick_sphere = new THREE.Mesh(g, light_material);
// 		pick_sphere.position.set(light_hash[hash].p.x, light_hash[hash].p.y, light_hash[hash].p.z)
// 		scene.add(pick_sphere);
// 		// pick_sphere = new THREE.Mesh(g, material3);
// 		// pick_sphere.position.set(
// 		// 	light_hash[hash].p.x + light_hash[hash].n.x * 0.1, 
// 		// 	light_hash[hash].p.y + light_hash[hash].n.y * 0.1, 
// 		// 	light_hash[hash].p.z + light_hash[hash].n.z * 0.1)
// 		// scene.add(pick_sphere);
// 	}
// }

// for (let i = 0; i < 14; i++)
// 	faces[i].geometry.setAttribute('lightness', new THREE.BufferAttribute(new Float32Array([1.0, 1.0, 0.7, 0.7]), 1));
for (let i = 0; i < faces.length; i++) {
	let face = faces[i].face;
	let light_hashes = faces[i].light_hashes;
	let lightnesses = [];
	for (let k = 0; k < 4; k++)
		lightnesses.push(light_hash[light_hashes[k]].lightness);
	face.geometry.setAttribute('lightness', new THREE.BufferAttribute(new Float32Array(lightnesses), 1));
}

var light_cam = new THREE.PerspectiveCamera(160, 1.0, 0.001, 1000);
// light_cam.rotation.x = Math.PI / 2;

// renderer.toneMapping = THREE.ACESFilmicToneMapping;
// renderer.toneMappingExposure = 2;
// renderer.outputEncoding = THREE.sRGBEncoding;

var light_hash_index = 0;

// Render Loop
var render = function () {
	requestAnimationFrame(render);
	let t = clock.getElapsedTime();
	// light_cam.matrix.set(faces[0].matrix.clone());
	// light_cam.matrix.makeRotationZ(Math.PI);
	
	// if (clock.elapsedTime < 1.0)
		// console.log(camera.position);
	
	// light_cam.position.x = camera.position.x;
	// light_cam.position.y = 1.005;
	// light_cam.position.z = camera.position.z;
	cam.animate_to(Math.floor(t * 200));
	camera.position.set(cam.from.x, cam.from.y + Math.sin(t * 3) * 0.01, cam.from.z);
	camera.rotation.set(0, 0, 0);
	camera.rotateOnAxis(new THREE.Vector3(0, 1, 0), cam.yaw);
	camera.rotateOnAxis(new THREE.Vector3(1, 0, 0), cam.pitch);
	camera.rotateOnAxis(new THREE.Vector3(0, 0, 1), cam.roll);
	for (let i = 0; i < 10; i++) {
		// light_cam.(faces[i].matrix);
		// let hash = faces[294].light_hashes[2];
		document.querySelector('#stats').innerHTML = `Faces:  ${face_count}, Light probe points: ${light_hash_index} / ${Object.keys(light_hash).length}`;

		if (USE_LIGHT_MAPS && light_hash_index < all_light_hashes.length) {
			let hash = all_light_hashes[light_hash_index];
			light_hash_index += 1;
			light_cam.position.set(light_hash[hash].p.x, light_hash[hash].p.y, light_hash[hash].p.z);
			if (light_hash[hash].dir < 6) {
				// let n = light_hash[hash].n;
				// light_cam.lookAt(light_hash[hash].p.x + n.x, light_hash[hash].p.y + n.y, light_hash[hash].p.z + n.z);
				// lm_renderer.setRenderTarget(renderTarget);
				// lm_renderer.setSize(renderTarget.width, renderTarget.height);
				// lm_renderer.render(light_scene, light_cam);
				// let buffer = new Uint8Array(LIGHT_ΜAP_SIZE * LIGHT_ΜAP_SIZE * 4);
				// lm_renderer.readRenderTargetPixels(renderTarget, 0, 0, LIGHT_ΜAP_SIZE, LIGHT_ΜAP_SIZE, buffer);
				// let sum = 0;
				// for (let k = 0; k < LIGHT_ΜAP_SIZE * LIGHT_ΜAP_SIZE; k++)
				// 	sum += buffer[k << 2];
				// sum /= LIGHT_ΜAP_SIZE * LIGHT_ΜAP_SIZE * 255;
				// sum = Math.pow(sum, 0.45);
				sum = Math.random() * 0.2 + 0.8;
				light_hash[hash].lightness = sum;
				// for (let j of light_hash[hash].faces) {
				// 	let face = faces[j].face;
				// 	let light_hashes = faces[j].light_hashes;
				// 	let lightnesses = [];
				// 	for (let k = 0; k < 4; k++)
				// 		lightnesses.push(light_hash[light_hashes[k]].lightness);
				// 	face.geometry.setAttribute('lightness', new THREE.BufferAttribute(new Float32Array(lightnesses), 1));
				// }
			}
			if (light_hash_index === all_light_hashes.length) {
				light_hash_index += 1;
				for (let j = 0; j < faces.length; j++) {
					let face = faces[j].face;
					let light_hashes = faces[j].light_hashes;
					let lightnesses = [];
					for (let k = 0; k < 4; k++)
						lightnesses.push(light_hash[light_hashes[k]].lightness);
					face.geometry.setAttribute('lightness', new THREE.BufferAttribute(new Float32Array(lightnesses), 1));
				}
			}
		}
	}
	renderer.setRenderTarget(null);
	renderer.setSize(window.innerWidth, window.innerHeight);
	// effect.render(scene, camera);
	let x = Math.floor(camera.position.x);
	let sector = MAP_SECTOR_FOR_X[x];
	for (let i = 0; i < GROUPS.length; i++) {
		GROUPS[i].visible = i >= sector - 2 && i <= sector + 2;
	}
	renderer.render(scene, camera);
	// console.log();

	let frustum = new THREE.Frustum();
	frustum.setFromProjectionMatrix(new THREE.Matrix4().multiplyMatrices( camera.projectionMatrix, camera.matrixWorldInverse ));

	// for (let el of labels) {
	// 	let hash = el.dataset.hash;
	// 	if (frustum.containsPoint(light_hash[hash].p)) {
	// 		let p2 = light_hash[hash].p.clone().project(camera);
	// 		let x = (p2.x / p2.z) * window.innerWidth / 2 + window.innerWidth / 2;
	// 		let y = (-p2.y / p2.z) * window.innerHeight / 2 + window.innerHeight / 2;
	// 		el.style.left = `${Math.round(x)}px`;
	// 		el.style.top = `${Math.round(y)}px`;
	// 		el.style.display = 'inline-block';
	// 	} else {
	// 		el.style.display = 'none';
	// 	}
	// }
	
	if (keys.left) cam.pan(0.7);
	if (keys.right) cam.pan(-0.7);
	if (keys.up) cam.tilt(-0.7);
	if (keys.down) cam.tilt(0.7);
	if (keys.forward) cam.dolly(-0.7);
	if (keys.backwards) cam.dolly(0.7);
	if (keys.strafe_up) cam.boom(1);
	if (keys.strafe_down) cam.boom(-1);
	if (keys.strafe_left) cam.truck(-1);
	if (keys.strafe_right) cam.truck(1);
	// if (keys.jump) cam.velocity.y = 0.05;
	if (keys.lightmap) light_hash_index = 0;
};

render();

function resize_handler() {
	renderer.setSize(window.innerWidth, window.innerHeight);
	camera.aspect = window.innerWidth / window.innerHeight;
	camera.updateProjectionMatrix();
}

window.addEventListener('resize', () => {
	resize_handler();
});

window.addEventListener('keydown', function (e) {
	for (let k in KEYS) if (e.code === k)
		keys[KEYS[k]] = true;
	if (e.key === 'm') face_material.wireframe = !face_material.wireframe;
});

window.addEventListener('keyup', function (e) {
	for (let k in KEYS) if (e.code === k)
		keys[KEYS[k]] = false;
});

