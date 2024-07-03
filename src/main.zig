const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");

const Allocator = std.mem.Allocator;

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);

/// Procedure table that will hold loaded OpenGL functions.
var gl_procs: gl.ProcTable = undefined;

pub const PositionArray = struct {
    NumberOfElem: usize,
    items: [][2]f32,
    allocator: Allocator,

    fn init(allocator: Allocator) !PositionArray {
        return .{
            .NumberOfElem = 0,
            .allocator = allocator,
            .items = try allocator.alloc([2]f32, 4),
        };
    }

    fn deinit(self: PositionArray) void {
        self.allocator.free(self.items);
    }

    fn add(self: *PositionArray, value: [2]f32) !void {
        const numberOfElem = self.NumberOfElem;
        const len = self.items.len;

        if (numberOfElem == len) {
            // we've run out of space
            // create a new slice that's twice as large
            var larger = try self.allocator.alloc([2]f32, len * 2);

            // copy the items we previously added to our new space
            @memcpy(larger[0..len], self.items);
            self.allocator.free(self.items);
            self.items = larger;
        }

        self.items[numberOfElem] = value;
        self.NumberOfElem = numberOfElem + 1;
    }
};

const Vertex = extern struct {
    position: Position,
    color: Color,

    const Position = [2]f32;
    const Color = [3]f32;
};

const PolygonMesh = struct {
    vertices: []const Vertex, // will become the vbo
    indices: []const i8, // will become the associated ibo
    program: c_uint,
    VBO: c_uint,
    IBO: c_uint,
};

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    glfw_log.err("{}: {s}\n", .{ error_code, description });
}

// This name is maybe not quite right
fn initializeProgram(vertexShader: [:0]const u8, fragmentShader: [:0]const u8) !c_uint {
    var success: c_int = undefined;
    var info_log_buf: [512:0]u8 = undefined;

    const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
    if (vertex_shader == 0) {
        return error.CreateVertexShaderFailed;
    }
    defer gl.DeleteShader(vertex_shader);

    gl.ShaderSource(
        vertex_shader,
        1,
        (&vertexShader.ptr)[0..1],
        (&@as(c_int, @intCast(vertexShader.len)))[0..1],
    );
    gl.CompileShader(vertex_shader);
    gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
    if (success == gl.FALSE) {
        gl.GetShaderInfoLog(vertex_shader, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.CompileVertexShaderFailed;
    }

    const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
    if (fragment_shader == 0) return error.CreateFragmentShaderFailed;
    defer gl.DeleteShader(fragment_shader);

    gl.ShaderSource(
        fragment_shader,
        1,
        (&fragmentShader.ptr)[0..1],
        (&@as(c_int, @intCast(fragmentShader.len)))[0..1],
    );
    gl.CompileShader(fragment_shader);
    gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success);
    if (success == gl.FALSE) {
        gl.GetShaderInfoLog(fragment_shader, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.CompileFragmentShaderFailed;
    }

    const program = gl.CreateProgram();
    if (program == 0) return error.CreateProgramFailed;
    errdefer gl.DeleteProgram(program);

    gl.AttachShader(program, vertex_shader);
    gl.AttachShader(program, fragment_shader);
    gl.LinkProgram(program);
    gl.GetProgramiv(program, gl.LINK_STATUS, &success);
    if (success == gl.FALSE) {
        gl.GetProgramInfoLog(program, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.LinkProgramFailed;
    }

    return program;
}

// In the future this function can be adapted to accept arrays for vbo and ibo, to bind multiple meshes to the VAO.
fn bindMeshToVAO(vao: c_uint, polygonMesh: PolygonMesh) void {
    // Make our VAO the current global VAO, but unbind it when we're done so we don't end up
    // inadvertently modifying it later.
    gl.BindVertexArray(vao);
    defer gl.BindVertexArray(0);

    {
        // Make our VBO the current global VBO and unbind it when we're done.
        gl.BindBuffer(gl.ARRAY_BUFFER, polygonMesh.VBO);
        defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

        // Upload vertex data to the VBO.
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @sizeOf(Vertex) * @as(isize, @intCast(polygonMesh.vertices.len)),
            @ptrCast(polygonMesh.vertices),
            gl.STATIC_DRAW,
        );

        // Instruct the VAO how vertex position data is laid out in memory.
        const position_attrib: c_uint = @intCast(gl.GetAttribLocation(polygonMesh.program, "a_Position"));
        gl.EnableVertexAttribArray(position_attrib);
        gl.VertexAttribPointer(
            position_attrib,
            @typeInfo(Vertex.Position).Array.len,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "position"),
        );

        // Ditto for vertex colors.
        const color_attrib: c_uint = @intCast(gl.GetAttribLocation(polygonMesh.program, "a_Color"));
        gl.EnableVertexAttribArray(color_attrib);
        gl.VertexAttribPointer(
            color_attrib,
            @typeInfo(Vertex.Color).Array.len,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "color"),
        );
    }

    // Instruct the VAO to use our IBO, then upload index data to the IBO.
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, polygonMesh.IBO);
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @sizeOf(u8) * @as(isize, @intCast(polygonMesh.indices.len)),
        @ptrCast(polygonMesh.indices),
        gl.STATIC_DRAW,
    );

    return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Move this into a glfwInit function?
    glfw.setErrorCallback(logGLFWError);

    if (!glfw.init(.{})) {
        glfw_log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInitFailed;
    }
    defer glfw.terminate();

    // Create our window, specifying that we want to use OpenGL.
    const window = glfw.Window.create(640, 480, "mach-glfw + OpenGL", null, null, .{
        .samples = 0,
        .context_version_major = gl.info.version_major,
        .context_version_minor = gl.info.version_minor,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
    }) orelse {
        glfw_log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.CreateWindowFailed;
    };
    defer window.destroy();

    // Make the window's OpenGL context current.
    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    // Enable VSync to avoid drawing more often than necessary.
    glfw.swapInterval(1);

    // Initialize the OpenGL procedure table.
    if (!gl_procs.init(glfw.getProcAddress)) {
        gl_log.err("failed to load OpenGL functions", .{});
        return error.GLInitFailed;
    }

    // Make the OpenGL procedure table current.
    gl.makeProcTableCurrent(&gl_procs);
    defer gl.makeProcTableCurrent(null);

    const vertexShader = @embedFile("shaders/SimpleVertexShader.vert");
    const fragmentShader = @embedFile("shaders/SimpleFragmentShader.frag");

    const polygonProgram = try initializeProgram(vertexShader, fragmentShader);
    defer gl.DeleteProgram(polygonProgram);

    // Vertex Buffer Object (VBO), holds vertex data.
    var hexagonVBO: c_uint = undefined;
    gl.GenBuffers(1, (&hexagonVBO)[0..1]);
    defer gl.DeleteBuffers(1, (&hexagonVBO)[0..1]);

    // Index Buffer Object (IBO), maps indices to vertices (to enable reusing vertices).
    var hexagonIBO: c_uint = undefined;
    gl.GenBuffers(1, (&hexagonIBO)[0..1]);
    defer gl.DeleteBuffers(1, (&hexagonIBO)[0..1]);

    const hexagonMesh = PolygonMesh{
        // zig fmt: off
        .vertices = &[_]Vertex{
            .{ .position = .{ -1, 0 }, .color = .{ 0, 0, 1 } },
            .{ .position = .{ -0.5, -0.866 }, .color = .{ 0, 0, 1 } },
            .{ .position = .{ -0.5, 0.866 }, .color = .{ 0, 0, 1 } },
            .{ .position = .{ 0.5, -0.866 }, .color = .{ 0, 0, 1 } },
            .{ .position = .{ 0.5, 0.866 }, .color = .{ 0, 0, 1 } },
            .{ .position = .{ 1, 0 }, .color = .{ 0, 0, 1 } },
        },
        // zig fmt: on
        .indices = &[_]i8{
            0, 3, 1,
            0, 4, 3,
            0, 2, 4,
            3, 4, 5,
        },
        .program = polygonProgram,
        .VBO = hexagonVBO,
        .IBO = hexagonIBO,
    };

    // Vertex Array Object (VAO), remembers instructions for how vertex data is laid out in memory.
    var VAO: c_uint = undefined;
    gl.GenVertexArrays(1, (&VAO)[0..1]);
    defer gl.DeleteVertexArrays(1, (&VAO)[0..1]);

    bindMeshToVAO(VAO, hexagonMesh);

    // This + the uniforms id like to see be taken care of in the hexagonMesh struct
    var hexagonPositionArray = try PositionArray.init(allocator);
    defer hexagonPositionArray.deinit();

    const framebuffer_size_uniform = gl.GetUniformLocation(polygonProgram, "u_FramebufferSize");
    const hexagonPosition_uniform = gl.GetUniformLocation(polygonProgram, "u_hexagonPosition");
    const angle_uniform = gl.GetUniformLocation(polygonProgram, "u_Angle");

    // because we have only one VAO we can bind this outside the main loop.
    gl.BindVertexArray(VAO);
    defer gl.BindVertexArray(0);

    // Same thing here, we only use one program so we can just leave this binded outside the main loop.
    gl.UseProgram(hexagonMesh.program);
    defer gl.UseProgram(0);

    main_loop: while (true) {
        glfw.pollEvents();
        // try hexagonPositionArray.add(.{ @as(f32, @floatFromInt(@as(i32, (@intCast(hexagonPositionArray.NumberOfElem))))) / 100.0, @floatFromInt(1) });

        if (window.shouldClose()) break :main_loop;
        {
            gl.ClearColor(1, 1, 1, 1);
            gl.Clear(gl.COLOR_BUFFER_BIT);

            // Make sure any changes to the window's size are reflected.
            const framebuffer_size = window.getFramebufferSize();
            gl.Viewport(0, 0, @intCast(framebuffer_size.width), @intCast(framebuffer_size.height));
            gl.Uniform2f(framebuffer_size_uniform, @floatFromInt(framebuffer_size.width), @floatFromInt(framebuffer_size.height));

            // for (hexagonPositionArray.items) |hexagonPosition| {
            gl.Uniform2f(hexagonPosition_uniform, 0.5, 0.0);
            gl.Uniform1f(angle_uniform, 0.1);
            gl.DrawElements(gl.TRIANGLES, @intCast(hexagonMesh.indices.len), gl.UNSIGNED_BYTE, 0);
            // }
        }

        window.swapBuffers();
    }
}
