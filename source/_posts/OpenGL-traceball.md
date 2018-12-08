---
title: OpenGL traceball
date: 2016-11-21 20:48:43
tags: OpenGL
---

这是图形学的一个作业，记录在此。

这次作业要求实现一个 traceball，需求如下：

1. 鼠标按住滑动，物体跟随鼠标转动
2. 滑动后释放鼠标，则物体保持最后旋转方向继续转动
3. 直接点击则可以停止旋转

现在需要把三个要求转换为程序实现，这里使用 freeglut 库开发。

<!-- more -->

## 设计

设计时需要考虑到的问题主要有下面两点。

### 物体旋转

OpenGL 中旋转通过 `glRotate*()` 函数实现，该函数需要提供两种含义的参数：1、旋转角度；2、旋转轴矢量。即用户改变旋转状态时，只需找出旋转角度与旋转轴矢量。除此之外，具体实现时我们还需要记录旋转前的状态，即每次绘制图像时先旋转到先前位置，然后进行下一步旋转。因此，多个旋转组合，理论上左乘顺序，依次给出旋转的矩阵。然而CTM实现是右乘属性。这里用栈操作实现不了顺序，只能靠自己编程设置矩阵保存上次旋转后的组合矩阵，再CTM右乘它。公式为：

```
初始：CTM(0)=I, M(0)=I

CTM(i)=I*R(i)*M(i-1); 
M(i)=CTM(i）;
```

### 鼠标跟随

这里假设我们的视点放在 Z 轴上，方向朝向远点，正方向为上。因此我们可以把屏幕上任意一点看成(x, y, 0)，方便后续计算。OpenGL 提供了鼠标相关回掉设置，可以监听鼠标移动和点击事件。对于鼠标移动，可以每次记录当前位置和前一刻位置，算出鼠标移动矢量 a。算出与矢量 a 垂直的平面，可以算出 xoy 平面和该平面的交线即为旋转轴。旋转角度则可以通过旋转方向矢量长度计算。

现在可以监听鼠标按键信息，按下表示开始旋转，弹起表示监控旋转结束；如果按下和弹起位置一样，那么停止旋转，否则继续保持旋转。

## Code

下面直接给出源码，其中有部分完成作业中其他需求部分也保留了。

```
#include <math.h>
#include <stdlib.h>
#include <GL/glut.h>

#define PI 3.1415926

#define ORITHOGRAPHIC 1
#define PERSPECTIVE   2

typedef GLfloat Point3f[3];

void Idle(void);
void Gasket(void);
void Render(void);
void Initialize(void);
void Reshape(int w, int h);
void Perspective(int w, int h);
void MouseMotion(int x, int y);
void Orthographic(int w, int h);
void Keyboard(unsigned char key, int x, int y);
void MouseEvent(int button, int state, int x, int y);

int gProjectStyle;
int gWindowWidth, gWindowHeight;
int gCurrentX, gCurrentY;
int gStartX, gStartY;
int gGasketLevel;

// lookAt 相关
GLfloat gZNear = 3.f, gZFar = 10.f;
GLfloat gZeye = 5.f;

// trackball 相关
GLfloat gLastPosition[3] = { 0.f, 0.f, 0.f };
GLfloat gAxis[3] = { 0.f, 0.f, 0.1f };
GLfloat gAngle = 0.f;
bool gIsRedrawContinue = false;

// 保存矩阵
GLfloat CompositeTransMatrix[4][4];

int main(int argc, char **argv)
{
    gWindowWidth = gWindowHeight = 600;

    glutInit(&argc, argv);
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB | GLUT_DEPTH);
    glutInitWindowSize(gWindowWidth, gWindowHeight);
    glutCreateWindow("trackball Color Gasket");

    Initialize();

    glutMainLoop();
}

void Identity(GLfloat matrix[4][4])
{
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 4; ++j) {
            matrix[i][j] = i == j ? 1.f : 0.f;
        }
    }
}

void MenuSelect(int item)
{
    if (item == ORITHOGRAPHIC) {
        Orthographic(gWindowWidth, gWindowHeight);
        gProjectStyle = ORITHOGRAPHIC;
        glutPostRedisplay();
    }
    else if (item == PERSPECTIVE) {
        Perspective(gWindowWidth, gWindowHeight);
        gProjectStyle = PERSPECTIVE;
        glutPostRedisplay();
    }
}

void InitMenu(void)
{
    glutCreateMenu(MenuSelect);
    glutAddMenuEntry("Orthographic", ORITHOGRAPHIC);
    glutAddMenuEntry("Perspective", PERSPECTIVE);
    glutAttachMenu(GLUT_RIGHT_BUTTON);
}

void InitCallback(void)
{
    glutReshapeFunc(Reshape);
    glutDisplayFunc(Render);
    glutIdleFunc(Idle);
    glutMouseFunc(MouseEvent);
    glutMotionFunc(MouseMotion);
    glutKeyboardFunc(Keyboard);
}

void Initialize(void)
{
    InitCallback();
    InitMenu();

    gGasketLevel = 3;
    Identity(CompositeTransMatrix);

    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_FLAT);
    glClearColor(1.0, 1.0, 1.0, 1.0);

    gProjectStyle = ORITHOGRAPHIC;
    Orthographic(gWindowWidth, gWindowHeight);
}

void Reshape(int w, int h)
{
    if (gProjectStyle == ORITHOGRAPHIC)
        Orthographic(w, h);
    else
        Perspective(w, h);
}

void Idle(void)
{
    if (gIsRedrawContinue == true) {
        gAngle = 0.01f;
        glutPostRedisplay();
    }
}

// 
// 计算透视窗口
// 
void CalView(int w, int h, GLfloat *left, GLfloat *right, GLfloat *bottom, GLfloat *top)
{
    if (w <= h) {
        *left = -2.0f;
        *right = 2.0f;
        *bottom = -2.0f * h / w;
        *top = 2.0f * h / w;
    } 
    else {
        *left = -2.0f * w / h;
        *right = 2.0f * w / h;
        *bottom = -2.0f;
        *top = 2.0f;
    }
}

void Perspective(int w, int h)
{
    GLfloat left, right, bottom, top;
    CalView(w, h, &left, &right, &bottom, &top);

    glViewport(0, 0, w, h);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(left, right, bottom, top, gZNear, gZFar);
    glutPostRedisplay();

    gWindowWidth = w;
    gWindowHeight = h;
}

void Orthographic(int w, int h)
{
    GLfloat left, right, bottom, top;
    CalView(w, h, &left, &right, &bottom, &top);

    glViewport(0, 0, w, h);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(left, right, bottom, top, gZNear, gZFar);
    glMatrixMode(GL_MODELVIEW);
    glutPostRedisplay();

    gWindowWidth = w;
    gWindowHeight = h;
}

// 
// 将屏幕坐标转换到 vector3f
// 
void TrackballPToV(int x, int y, int w, int h, GLfloat v[3])
{
    v[0] = (2.0f*x - w) / w;
    v[1] = (h - 2.0f*y) / h;
    float d = sqrtf(v[0] * v[0] + v[1] * v[1]);
    v[2] = cosf((PI / 2.0f) * ((d < 1.0f) ? d : 1.0f));
    float a = 1.0f / sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    v[0] *= a;
    v[1] *= a;
    v[2] *= a;
}

void MouseMotion(int x, int y)
{
    float curPos[3], dx, dy, dz;
    TrackballPToV(x, y, gWindowWidth, gWindowHeight, curPos);

    dx = curPos[0] - gLastPosition[0];
    dy = curPos[1] - gLastPosition[1];
    dz = curPos[2] - gLastPosition[2];

    if (dx || dy || dz) {
        gAngle = 90.0F * sqrtf(dx*dx + dy*dy + dz*dz);

        gAxis[0] = gLastPosition[1] * curPos[2] - gLastPosition[2] * curPos[1];
        gAxis[1] = gLastPosition[2] * curPos[0] - gLastPosition[0] * curPos[2];
        gAxis[2] = gLastPosition[0] * curPos[1] - gLastPosition[1] * curPos[0];

        gLastPosition[0] = curPos[0];
        gLastPosition[1] = curPos[1];
        gLastPosition[2] = curPos[2];
    }

    glutPostRedisplay();
}

void StartMotion(int x, int y)
{
    gIsRedrawContinue = false;
    gStartX = x; 
    gStartY = y;
    gCurrentX = x;
    gCurrentY = y;
    TrackballPToV(x, y, gWindowWidth, gWindowHeight, gLastPosition);
}

void StopMotion(int x, int y)
{
    if (gStartX != x && gStartY != y) {
        gIsRedrawContinue = true;
    }
    else {
        gAngle = 0.0f;
        gIsRedrawContinue = false;
    }
}

void MouseEvent(int Botton, int State, int MouseX, int MouseY)
{
    if (Botton == GLUT_LEFT_BUTTON) {
        switch (State)
        {
        case GLUT_DOWN:
            StartMotion(MouseX, MouseY);
            break;
        case GLUT_UP:
            StopMotion(MouseX, MouseY);
            break;
        }
    }
}

void Render(void)
{
    GLfloat *pCompositeTransMatrix = *CompositeTransMatrix;

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    /* 多个旋转组合 */
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glRotatef(gAngle, gAxis[0], gAxis[1], gAxis[2]);
    glMultMatrixf(pCompositeTransMatrix);
    glGetFloatv(GL_MODELVIEW_MATRIX, pCompositeTransMatrix);

    // 设置 lookAtMatrix 应该在最开始的位置
    glLoadIdentity();
    gluLookAt(0, 0, gZeye, 0, 0, 0, 0, 1, 0);
    glMultMatrixf(pCompositeTransMatrix);

    Gasket();

    glutSwapBuffers();
}

void Keyboard(unsigned char key, int x, int y)
{
    if ('0' <= key && key <= '3') {
        gGasketLevel = key - '0';
        glutPostRedisplay();
    }
    else if (key == 'q' || key == 'Q') {
        exit(0);
    }
}

void Triangle(const Point3f p1, const Point3f p2, const Point3f p3, const Point3f color)
{
    glBegin(GL_POLYGON);
    {
        glColor3fv(color);
        glVertex3fv(p1);
        glVertex3fv(p2);
        glVertex3fv(p3);
    }
    glEnd();
}

void Tetrahedron(const Point3f p1, const Point3f p2, const Point3f p3, const Point3f p4)
{
    const static Point3f Color[] = {
        { 1.f, 0.f, 0.f },
        { 0.f, 1.f, 0.f },
        { 0.f, 0.f, 1.f },
        { 1.f, 1.f, 0.1f },
    };

    Triangle(p1, p2, p3, Color[0]);
    Triangle(p1, p2, p4, Color[1]);
    Triangle(p1, p3, p4, Color[2]);
    Triangle(p2, p4, p3, Color[3]);
}

void DivideVertices(Point3f p1, Point3f p2, Point3f p3, Point3f p4, int level)
{
    Point3f v0, v1, v2, v3, v4, v5;
    if (level > 0) {
        for (int j = 0; j<3; j++) v0[j] = (p1[j] + p2[j]) / 2;
        for (int j = 0; j<3; j++) v1[j] = (p1[j] + p3[j]) / 2;
        for (int j = 0; j<3; j++) v2[j] = (p1[j] + p4[j]) / 2;
        for (int j = 0; j<3; j++) v3[j] = (p2[j] + p3[j]) / 2;
        for (int j = 0; j<3; j++) v4[j] = (p2[j] + p4[j]) / 2;
        for (int j = 0; j<3; j++) v5[j] = (p4[j] + p3[j]) / 2;
        DivideVertices(p1, v0, v1, v2, level - 1);
        DivideVertices(v0, p2, v3, v4, level - 1);
        DivideVertices(v1, v3, p3, v5, level - 1);
        DivideVertices(v2, v4, v5, p4, level - 1);
    } 
    else {
        Tetrahedron(p1, p2, p3, p4);
    }
}

void Gasket(void)
{
    static Point3f Vertices[] = {
        { -1.f, -1.f, 0.5773f },
        { 0.f, -1.f, -1.15475 },
        { 1.0f, -1.0f, 0.5773f },
        { 0.0f, 1.0f, 0.0f },
    };
    DivideVertices(Vertices[0], Vertices[1], Vertices[2], Vertices[3], gGasketLevel);
}
```