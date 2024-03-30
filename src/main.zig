const rl = @import("raylib");
const math = @import("raylib-math");
const std = @import("std");
const dbg = std.debug;
const rand = std.crypto.random;
const allocator = std.heap.page_allocator; // slow but simple. Fine for this game

const screenWidth = 900;
const screenHeight = 800;

const Object = struct {
    model: std.ArrayList(rl.Vector2),
    pos: rl.Vector2,
    force: rl.Vector2,
    rotation: f32 = 0, // in radians

    pub fn draw(self: @This()) void {
        const mat = math.matrixRotateZ(self.rotation);
        for (self.model.items,0..) |_,i| {
            var j: usize = i + 1;
            if (j == self.model.items.len) j = 0;
            const p1 = math.vector2Add(math.vector2Transform(self.model.items[i],mat),self.pos);
            const p2 = math.vector2Add(math.vector2Transform(self.model.items[j],mat),self.pos);
            rl.drawLineEx(p1,p2, 2, rl.Color.white);
        }
    }
    pub fn move(self: *@This()) void {
        var x = self.pos.x + self.force.x;
        var y = self.pos.y + self.force.y;
        if (y < 0) y += screenHeight;
        if (screenHeight < y) y -= screenHeight;
        if (x < 0) x += screenWidth;
        if (screenWidth < x) x -= screenWidth;
        self.pos = rl.Vector2.init(x, y);
    }
    pub fn getDirection(self: @This()) rl.Vector2 {
        const x = @sin(self.rotation);
        const y = @cos(self.rotation);
        return math.vector2Normalize(rl.Vector2.init(x, -y));
    }

    pub fn destroy(self: @This()) void {
        self.model.deinit();
    }
};

const Projectile = struct {
    pos: rl.Vector2,
    direction: rl.Vector2,
    lifeTime: u32 = 100,
    age: u32 = 0,

    pub fn draw(self: @This()) void {
        rl.drawCircleV(self.pos,2,rl.Color.white);
    }
    pub fn move(self: *@This()) void {
        var x = self.pos.x + self.direction.x;
        var y = self.pos.y + self.direction.y;
        if (y < 0) y += screenHeight;
        if (screenHeight < y) y -= screenHeight;
        if (x < 0) x += screenWidth;
        if (screenWidth < x) x -= screenWidth;
        self.pos = rl.Vector2.init(x, y);
        self.age += 1;
    }
};

const Ship = struct {
    sprite: Object,
    animation: [3]rl.Vector2,
    off: bool = false,

    pub fn spawn(position: rl.Vector2) !@This() {
        var model = std.ArrayList(rl.Vector2).init(allocator);
        try model.append(rl.Vector2.init(0,-20));
        try model.append(rl.Vector2.init(-10, 10));
        try model.append(rl.Vector2.init(0, 5));
        try model.append(rl.Vector2.init(10,10));
        return .{
            .sprite = .{
                .model = model,
                .pos = position,
                .force = rl.Vector2.init(0, 0)
            },
            .animation = [_]rl.Vector2 {
                rl.Vector2.init(-5,2.5),
                rl.Vector2.init(0, 15),
                rl.Vector2.init(5,2.5)
            }
        };
    }

    pub fn animate(self: @This()) void {
        if (self.off) return;
        const mat = math.matrixRotateZ(self.sprite.rotation);
        for (self.animation,1..) |point,i| {
            var index = i;
            if (index == self.animation.len) index = 0;
            rl.drawLineEx(math.vector2Add(math.vector2Transform(point,mat),self.sprite.pos),
            math.vector2Add(math.vector2Transform(self.animation[index], mat),self.sprite.pos), 2, rl.Color.white);
        }
    }
};

const AsteroidType = enum {
    LARGE,
    MEDIUM,
    SMALL,

    pub fn size(self: @This()) f32 {
        return switch (self) {
            .LARGE => 2,
            .MEDIUM => 1,
            .SMALL => 0.3
        };
    }
};

const Asteroid = struct {
    sprite: Object,

    pub fn spawn(position: rl.Vector2,size: AsteroidType) @This() {
        var points = std.ArrayList(rl.Vector2).init(allocator);
        const step: f32 = (2 * std.math.pi) / 10.0;
        var current: f32 = 0.0;
        for (0..10) |_| {
            points.append(rl.Vector2.init(std.math.sin(current) * RandToF(30, 50) * size.size(),
            std.math.cos(current) * RandToF(15, 50) * size.size())) catch unreachable;
            current += step;
        }
        return .{
            .sprite = .{
                .model = points,
                .pos = position,
                .force = rl.Vector2.init(0, 0)
            }
        };
    }
};

const Game = struct {
    player: Ship,
    asteroids: std.ArrayList(Asteroid),
    projectiles: std.ArrayList(Projectile),
    radius: f32 = 120,
    level: u8 = 1,

    fn next(self: *@This()) void {
        var numOfAsteroids: u8 = self.level * 3;
        // zone 1 -> 4 asteroids only
        // zone 2 -> 7 asteroids only
        // zone n -> n^2 + 3 asteroids only

        // no zones past zone 3
        if (numOfAsteroids > 12){
            numOfAsteroids = 12;
            dbg.print("Too many asteroids: zones exceeded\nSetting amount to 12", .{});
        }
        // fill zones
        for (1..4) |i| {
            const index: u8 = @as(u8,@intCast(i));
            if (numOfAsteroids == 0) break;
            const amount: u8 = index*index + 3;
            var zone: u8 = 0;
            if (index == 3){ // last level
                zone = numOfAsteroids;
            } else zone = rand.intRangeAtMost(u8, self.level,if (amount > numOfAsteroids) numOfAsteroids else amount);
            // put asteroids at zone positions
            for (0..zone) |_| {
                const point: f32 = @as(f32,@floatFromInt(rand.intRangeAtMost(u32, 0,@as(u32,@intFromFloat((2 * std.math.pi) * 100000))))) / 100000;
                const x = @sin(point) * self.radius * @as(f32,@floatFromInt(index)) + @as(f32,@floatFromInt(screenWidth/2));
                const y = @cos(point) * self.radius * @as(f32,@floatFromInt(index)) + @as(f32,@floatFromInt(screenHeight/2));
                self.asteroids.append(Asteroid.spawn(rl.Vector2.init(x,y),rand.enumValue(AsteroidType))) catch unreachable;
            }

            numOfAsteroids -= zone;
        }

        self.level += 1;
    }
};

fn update(game: *Game) anyerror!void {
    // key input stuff
    if (rl.isKeyDown(rl.KeyboardKey.key_a)){
        game.player.sprite.rotation -= 0.1;
    } else if (rl.isKeyDown(rl.KeyboardKey.key_d)){
        game.player.sprite.rotation += 0.1;
    }
    if (rl.isKeyDown(rl.KeyboardKey.key_w)){
        game.player.off = !game.player.off;
        game.player.sprite.force = math.vector2Scale(game.player.sprite.getDirection(),5);
        game.player.animate();
    } else {
        // drag
        game.player.sprite.force = math.vector2Scale(game.player.sprite.force, 0.98);
    }
    if (rl.isKeyPressed(rl.KeyboardKey.key_space)){
        var proj = Projectile {
            .pos = game.player.sprite.pos,
            .direction = math.vector2Scale(game.player.sprite.getDirection(),10),
        };
        try game.projectiles.append(proj);
    }
    // game logic
    game.player.sprite.move();
    for (game.projectiles.items,0..) |*proj,i| {
        if (proj.age == proj.lifeTime){
            _ = game.projectiles.swapRemove(i);
            continue;
        }
        proj.move();
    }
}
fn draw(game: *Game) void {
    game.player.sprite.draw();
    for (game.projectiles.items) |proj| {
        proj.draw();
    }
    for (game.asteroids.items) |ast| {
        ast.sprite.draw();
    }
}

pub fn main() anyerror!void {

    rl.initWindow(screenWidth, screenHeight, "Asteroids");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var game = Game {
        .player = try Ship.spawn(rl.Vector2.init(screenWidth / 2,screenHeight / 2)),
        .asteroids = std.ArrayList(Asteroid).init(allocator),
        .projectiles = std.ArrayList(Projectile).init(allocator)
    };
    defer game.asteroids.deinit();
    defer game.projectiles.deinit();

    game.next();

    while (!rl.windowShouldClose()) {
        // update
        update(&game) catch unreachable;

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        draw(&game);
    }
}

fn RandToF(min: i32, max: i32) f32 {
    return @as(f32,@floatFromInt(rand.intRangeLessThan(i32, min, max)));
}