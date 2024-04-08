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
        for (self.model.items,1..) |raw,nextIndex| {
            const p1 = math.vector2Add(math.vector2Transform(self.model.items[if (nextIndex == self.model.items.len) 0 else nextIndex], mat), self.pos);
            const p2 = math.vector2Add(math.vector2Transform(raw, mat), self.pos);
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

    pub fn collison(self: @This(),point: rl.Vector2) bool {
        const mat = math.matrixRotateZ(self.rotation);
        for (self.model.items,1..) |raw,nextIndex| {
            const next = math.vector2Add(math.vector2Transform(self.model.items[if (nextIndex == self.model.items.len) 0 else nextIndex], mat), self.pos);
            const current = math.vector2Add(math.vector2Transform(raw, mat), self.pos);
            if (rl.checkCollisionPointTriangle(point,current,next,self.pos)) return true;
        }
        return false;
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

const Part = struct {
    model: [2]rl.Vector2,
    force: rl.Vector2
};

const Ship = struct {
    sprite: Object,
    animation: [3]rl.Vector2,
    off: bool = false,
    // death animation
    dead: bool = false,
    parts: [4]Part = undefined,
    timeOfDeath: i64 = 0,
    // cool down
    cooldown: bool = false,


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
    pub fn draw(self: *@This()) void {
        if (self.dead){
            for (self.parts) |part| rl.drawLineEx(part.model[0], part.model[1], 2, rl.Color.white);
        } else if (self.cooldown) {
            // immune 3s after respawn
            const time = std.time.milliTimestamp() - self.timeOfDeath;
            if (time >= 6000){
                self.cooldown = false;
            } else {
                // cool down animation
                if (@mod(@divFloor(time,300),2) == 1)
                    self.sprite.draw();
            }
        } else self.sprite.draw();
    }
    pub fn move(self: *@This()) void {
        if (self.dead){
            for (&self.parts) |*part| {
                for (part.model,0..) |point,i| part.model[i] = math.vector2Add(point,part.force);
            }
        } else self.sprite.move();
    }
    pub fn animate(self: @This()) void {
        if (self.dead) return;
        if (self.off) return;
        const mat = math.matrixRotateZ(self.sprite.rotation);
        for (self.animation,1..) |point,i| {
            var index = i;
            if (index == self.animation.len) index = 0;
            rl.drawLineEx(math.vector2Add(math.vector2Transform(point,mat),self.sprite.pos),
            math.vector2Add(math.vector2Transform(self.animation[index], mat),self.sprite.pos), 2, rl.Color.white);
        }
    }
    pub fn death(self: *@This()) void {
        const mat = math.matrixRotateZ(self.sprite.rotation);
        const speed = 0.5;
        for (0..4,1..) |s,e| {
            const dir = math.vector2Multiply(math.vector2Normalize(rl.Vector2.init(RandToF(-10,10),RandToF(-10,10))),rl.Vector2.init(speed, speed));
            const p2 = math.vector2Add(math.vector2Transform(self.sprite.model.items[if (e == self.sprite.model.items.len) 0 else e], mat), self.sprite.pos);
            const p1 = math.vector2Add(math.vector2Transform(self.sprite.model.items[s], mat), self.sprite.pos);
            self.parts[s] = .{
                .model = [2]rl.Vector2 {p1,p2},
                .force = dir
            };
        }
        self.dead = true;
        self.timeOfDeath = std.time.milliTimestamp();
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
            .SMALL => 0.3,
        };
    }
    pub fn degrade(self: @This()) !AsteroidType {
        return switch (self) {
            .LARGE => AsteroidType.MEDIUM,
            .MEDIUM => AsteroidType.SMALL,
            .SMALL => error.InvalidSize,
        };
    }
};

const Asteroid = struct {
    sprite: Object,
    size: AsteroidType,

    pub fn spawn(position: rl.Vector2,size: AsteroidType) @This() {
        var points = std.ArrayList(rl.Vector2).init(allocator);
        const step: f32 = (2 * std.math.pi) / 9.0;
        var current: f32 = 0.0;
        for (0..10) |_| {
            points.append(rl.Vector2.init(std.math.sin(current) * RandToF(30, 50) * size.size(),
            std.math.cos(current) * RandToF(15, 50) * size.size())) catch unreachable;
            current += step;
        }
        const dir = math.vector2Normalize(rl.Vector2.init(RandToF(-10,10),RandToF(-10,10)));
        const force = math.vector2Divide(dir, rl.Vector2.init(size.size(), size.size()));
        return .{
            .sprite = .{
                .model = points,
                .pos = position,
                .force = force
            },
            .size = size
        };
    }
};

const Game = struct {
    player: Ship,
    asteroids: std.ArrayList(Asteroid),
    projectiles: std.ArrayList(Projectile),
    radius: f32 = 120,
    score: usize = 0,
    level: u8 = 1,
    lives: u8 = 3,
    lastStageTime: i64 = 0,

    pub fn end(self: @This()) void {
        const text = "Game Over";
        const x = screenWidth / 2 - text.len * 24;
        const y = screenHeight / 2 - 100;
        rl.drawText(text,x,y, 64, rl.Color.white);
        if (std.fmt.allocPrintZ(allocator, "Level: {}\n\nScore: {}", .{self.level - 1,self.score})) |score| {
            rl.drawText(score, x, y + 100, 32, rl.Color.white);
        } else |_| {
            rl.drawText("Score exceeded allocated memory amount\n\nDamn lol", x, y + 100,32, rl.Color.white);
        }
        rl.endDrawing();
        rl.waitTime(10);
        self.asteroids.deinit();
        self.projectiles.deinit();
        rl.closeWindow();
        std.os.exit(0);
    }

    fn next(self: *@This()) void {
        dbg.print("Starting new stage: level {}\n", .{self.level});

        // move player to centre. Reset force
        self.player.sprite.force = rl.Vector2.init(0, 0);
        self.player.sprite.pos = rl.Vector2.init(screenWidth / 2, screenHeight / 2);

        self.lastStageTime = std.time.milliTimestamp();
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
    const time = std.time.milliTimestamp();

    if (game.asteroids.items.len == 0){
        game.next();
    }

    if (game.player.dead and time - game.player.timeOfDeath >= 3000){
        if (game.lives == 1) game.end();
        game.lives -= 1;
        game.player.cooldown = true;
        game.player.dead = false;
    }
    game.player.move();
    for (game.projectiles.items,0..) |*proj,i| {
        if (proj.age == proj.lifeTime){
            _ = game.projectiles.swapRemove(i);
            continue;
        }
        proj.move();
    }
    // collison
    const mat = math.matrixRotateZ(game.player.sprite.rotation);
    for (game.asteroids.items,0..) |*a,i| {
        a.sprite.move();
        // Maybe check all points on player instead of just centre
        if(!game.player.dead and !game.player.cooldown){
            for (game.player.sprite.model.items,0..) |point,j| {
                if (j == 2) continue;
                const check = math.vector2Add(math.vector2Transform(point, mat), game.player.sprite.pos);
                if (a.sprite.collison(check)){
                    // collison accoured! betweem player and asteroid
                    game.player.death();
                    break;
                }
            }
        }
        for (game.projectiles.items,0..) |proj,j| {
            if (a.sprite.collison(proj.pos)){
                _ = game.projectiles.swapRemove(j);
                defer {
                    a.sprite.destroy();
                     _ = game.asteroids.swapRemove(i);
                }
                game.score += switch (a.size) {
                    .LARGE => 40,
                    .MEDIUM => 50,
                    .SMALL => 100
                };
                if (a.size == AsteroidType.SMALL) return;
                const newType = try a.size.degrade();
                for (0..3) |_| {
                    const x = a.sprite.pos.x + RandToF(-20, 20);
                    const y = a.sprite.pos.y + RandToF(-20, 20);
                    try game.asteroids.append(Asteroid.spawn(rl.Vector2.init(x, y),newType));
                }
                break;
            }
        }
    }
}
fn draw(game: *Game) void {
    game.player.draw();
    for (game.projectiles.items) |proj| {
        proj.draw();
    }
    for (game.asteroids.items) |ast| {
        ast.sprite.draw();
    }
    // draw score
    if (std.fmt.allocPrintZ(allocator, "{}", .{game.score})) |score| {
        defer allocator.free(score);
        rl.drawText(score, 10, 10, 24, rl.Color.white);
    } else |_| {
        rl.drawText("0", 10, 10, 24, rl.Color.white);
    }
    // draw lives
    const model = game.player.sprite.model.items;
    for (0..game.lives) |i| {
        const shift = rl.Vector2.init(@as(f32,@floatFromInt(i)) * 25.0 + 20.0, 60);
        for (model,1..) |raw,nextIndex| {
            const p1 = math.vector2Add(model[if (nextIndex == model.len) 0 else nextIndex],shift);
            const p2 = math.vector2Add(raw,shift);
            rl.drawLineEx(p1,p2, 2, rl.Color.white);
        }
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
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        update(&game) catch unreachable;
        draw(&game);
    }
}

fn RandToF(min: i32, max: i32) f32 {
    return @as(f32,@floatFromInt(rand.intRangeAtMost(i32, min, max)));
}